import AppKit
import ImporterCore
import Observation
import SwiftUI

enum Step: Int, CaseIterable, Identifiable {
    case connect, pick, metadata, run, report

    var id: Self { self }

    var title: String {
        switch self {
        case .connect: "Verbinden"
        case .pick: "Fotos wählen"
        case .metadata: "Metadaten"
        case .run: "Import"
        case .report: "Bericht"
        }
    }

    var symbol: String {
        switch self {
        case .connect: "link"
        case .pick: "photo.on.rectangle"
        case .metadata: "tag"
        case .run: "square.and.arrow.down"
        case .report: "checklist"
        }
    }
}

enum RunState: Equatable {
    case idle, running, paused, finished
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String
}

@MainActor
@Observable
final class AppModel {
    private static let lightCraftBundleID = "ai.storyteller.lightcraft"

    var step: Step = .connect
    var fieldFilter: FieldStatus?
    var errorMessage: String?

    private(set) var sourceURL: URL?
    private(set) var destinationURL: URL?
    private(set) var destinationProblem: String?
    private(set) var library: ExportLibrary?
    private(set) var isScanning = false
    private(set) var scannedCount = 0

    var selectedAlbums: Set<String> = [] {
        didSet { refreshSelection() }
    }
    private(set) var selectedPhotos: [ExportPhoto] = []
    private(set) var coverage: [MetadataField: Int] = [:]

    private(set) var runState: RunState = .idle
    private(set) var fraction = 0.0
    private(set) var stage: ImportStage?
    private(set) var processed = 0
    private(set) var log: [LogEntry] = []
    private(set) var report: ImportReport?

    private var control: ImportControl?
    private var scanTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    #if DEBUG
    private var debugStep: Step?
    private var debugRun = false
    #endif

    var selectedBytes: Int64 {
        selectedPhotos.reduce(0) { $0 + $1.fileSize }
    }

    var isRunActive: Bool {
        runState == .running || runState == .paused
    }

    var lightCraftURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.lightCraftBundleID)
    }

    var lightCraftVersion: String? {
        lightCraftURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
    }

    var isReadyToContinue: Bool {
        library != nil && !isScanning && destinationURL != nil && destinationProblem == nil
    }

    func canOpen(_ target: Step) -> Bool {
        if isRunActive { return target == .run }
        switch target {
        case .connect: return true
        case .pick: return isReadyToContinue
        case .metadata, .run: return isReadyToContinue && !selectedPhotos.isEmpty
        case .report: return report != nil
        }
    }

    func go(to target: Step) {
        if canOpen(target) { step = target }
    }

    func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { go(to: next) }
    }

    func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { go(to: previous) }
    }

    // MARK: Folders

    func chooseSource() {
        let panel = folderPanel(message: "Wähle den Ordner mit deinem Lightroom-Export „Original + Einstellungen“.")
        if panel.runModal() == .OK, let url = panel.url { setSource(url) }
    }

    func chooseDestination() {
        let panel = folderPanel(message: "Wähle einen eigenen Ordner für die Kopien, nicht die LightCraft-Bibliothek.")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { setDestination(url) }
    }

    private func folderPanel(message: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        panel.message = message
        return panel
    }

    private func setSource(_ url: URL) {
        sourceURL = url
        library = nil
        selectedAlbums = []
        resetRun()
        validateFolders()
        scan(url)
    }

    private func setDestination(_ url: URL) {
        destinationURL = url
        resetRun()
        validateFolders()
    }

    private func validateFolders() {
        guard let sourceURL, let destinationURL else {
            destinationProblem = nil
            return
        }
        do {
            try ImportEngine.validate(source: sourceURL, destination: destinationURL)
            destinationProblem = nil
        } catch {
            destinationProblem = error.localizedDescription
        }
    }

    private func scan(_ root: URL) {
        scanTask?.cancel()
        isScanning = true
        scannedCount = 0
        let (stream, continuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let worker = Task.detached(priority: .userInitiated) { () -> Result<ExportLibrary, Error> in
            defer { continuation.finish() }
            do {
                let result = try ExportScanner.scan(
                    root: root,
                    isCancelled: { Task.isCancelled },
                    progress: { continuation.yield($0) }
                )
                return .success(result)
            } catch {
                return .failure(error)
            }
        }
        scanTask = Task { [weak self] in
            await withTaskCancellationHandler {
                for await count in stream {
                    self?.scannedCount = count
                }
            } onCancel: {
                worker.cancel()
            }
            let result = await worker.value
            guard !Task.isCancelled, let self else { return }
            self.isScanning = false
            switch result {
            case .success(let scanned):
                self.library = scanned
                self.selectedAlbums = Set(scanned.albums.map(\.id))
                if scanned.photos.isEmpty {
                    self.errorMessage = "In diesem Ordner wurden keine Fotos gefunden."
                }
                #if DEBUG
                self.applyPendingDebugActions()
                #endif
            case .failure(let error):
                if !(error is CancellationError) {
                    self.errorMessage = "Der Ordner konnte nicht gelesen werden: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Selection

    func isSelected(_ album: ExportAlbum) -> Bool {
        selectedAlbums.contains(album.id)
    }

    func setSelected(_ album: ExportAlbum, _ selected: Bool) {
        if selected {
            selectedAlbums.insert(album.id)
        } else {
            selectedAlbums.remove(album.id)
        }
    }

    func toggleAllAlbums() {
        guard let library else { return }
        selectedAlbums = selectedAlbums.count == library.albums.count ? [] : Set(library.albums.map(\.id))
    }

    private func refreshSelection() {
        selectedPhotos = library?.photos.filter { selectedAlbums.contains($0.album) } ?? []
        coverage = MetadataField.coverage(of: selectedPhotos)
        if !isRunActive { resetRun() }
    }

    // MARK: Import

    func startImport() {
        guard let library, let destinationURL, !selectedPhotos.isEmpty, !isRunActive else { return }
        let plan = ImportPlan(sourceRoot: library.root, destinationRoot: destinationURL, photos: selectedPhotos)
        let control = ImportControl()
        self.control = control
        report = nil
        fraction = 0
        processed = 0
        stage = nil
        log = [LogEntry(text: "Import gestartet")]
        runState = .running

        let (stream, continuation) = AsyncStream<ImportEvent>.makeStream()
        let worker = Task.detached(priority: .utility) { () -> Result<ImportReport, Error> in
            defer { continuation.finish() }
            do {
                return .success(try ImportEngine.run(plan: plan, control: control) { continuation.yield($0) })
            } catch {
                return .failure(error)
            }
        }
        runTask = Task { [weak self] in
            for await event in stream {
                self?.apply(event)
            }
            let result = await worker.value
            self?.finish(result)
        }
    }

    func togglePause() {
        switch runState {
        case .running:
            control?.pause()
            runState = .paused
            log.append(LogEntry(text: "Pausiert"))
        case .paused:
            control?.resume()
            runState = .running
            log.append(LogEntry(text: "Fortgesetzt"))
        default:
            break
        }
    }

    func cancelImport() {
        control?.cancel()
    }

    func startOver() {
        resetRun()
        step = .connect
    }

    private func apply(_ event: ImportEvent) {
        switch event {
        case .stage(let value):
            stage = value
        case .progress(let value, let done, _):
            fraction = value
            processed = done
        case .log(let text):
            log.append(LogEntry(text: text))
        }
    }

    private func finish(_ result: Result<ImportReport, Error>) {
        control = nil
        switch result {
        case .success(let finished):
            report = finished
            fraction = 1
            processed = selectedPhotos.count
            runState = .finished
        case .failure(let error):
            runState = .idle
            stage = nil
            fraction = 0
            processed = 0
            if error is CancellationError {
                log.append(LogEntry(text: "Abgebrochen. Fertige Kopien bleiben im Zielordner und werden beim nächsten Start erkannt."))
            } else {
                log.append(LogEntry(text: "Import fehlgeschlagen"))
                errorMessage = "Der Import ist fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    private func resetRun() {
        guard !isRunActive else { return }
        runState = .idle
        fraction = 0
        processed = 0
        stage = nil
        log = []
        report = nil
    }

    // MARK: Finder and LightCraft

    func revealDestination() {
        guard let destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func openLightCraft() {
        revealDestination()
        guard let lightCraftURL else { return }
        NSWorkspace.shared.openApplication(at: lightCraftURL, configuration: .init(), completionHandler: nil)
    }

    // MARK: Debug start arguments

    #if DEBUG
    /// `-debugSource <path> -debugDestination <path> -debugStep <0…4> -debugRun YES`
    func applyDebugArguments() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "debugStep") != nil {
            debugStep = Step(rawValue: defaults.integer(forKey: "debugStep"))
        }
        debugRun = defaults.bool(forKey: "debugRun")
        if let path = defaults.string(forKey: "debugDestination") {
            setDestination(URL(fileURLWithPath: path))
        }
        if let path = defaults.string(forKey: "debugSource") {
            setSource(URL(fileURLWithPath: path))
        }
    }

    private func applyPendingDebugActions() {
        if debugRun {
            debugRun = false
            step = .run
            startImport()
        } else if let debugStep {
            self.debugStep = nil
            go(to: debugStep)
        }
    }
    #endif
}
