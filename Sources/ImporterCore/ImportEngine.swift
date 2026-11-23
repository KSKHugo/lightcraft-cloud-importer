import CryptoKit
import Foundation

package enum ImportStage: Int, CaseIterable, Identifiable, Sendable {
    case hashing, copying, sidecars, report

    package var id: Int { rawValue }

    package var title: String {
        switch self {
        case .hashing: "Prüfsummen und Duplikate prüfen"
        case .copying: "Originale kopieren und gegenprüfen"
        case .sidecars: "XMP-Dateien übernehmen"
        case .report: "Bericht schreiben"
        }
    }
}

package enum ImportEvent: Sendable {
    case stage(ImportStage)
    case progress(fraction: Double, processed: Int, total: Int)
    case log(String)
}

package enum ImportValidationError: LocalizedError, Equatable {
    case destinationInsideSource
    case sourceInsideDestination
    case destinationIsLightCraftLibrary
    case noPhotos

    package var errorDescription: String? {
        switch self {
        case .destinationInsideSource: "Der Zielordner darf nicht im Export-Ordner liegen."
        case .sourceInsideDestination: "Der Export-Ordner darf nicht im Zielordner liegen."
        case .destinationIsLightCraftLibrary: "Der Zielordner darf nicht in der LightCraft-Bibliothek liegen. Wähle einen eigenen Ordner, LightCraft importiert ihn danach."
        case .noPhotos: "Es sind keine Fotos ausgewählt."
        }
    }
}

/// Pause and cancel, checked between chunks of file data.
package final class ImportControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var paused = false
    private var cancelled = false

    package init() {}

    package func pause() {
        condition.lock(); paused = true; condition.unlock()
    }

    package func resume() {
        condition.lock(); paused = false; condition.broadcast(); condition.unlock()
    }

    package func cancel() {
        condition.lock(); cancelled = true; condition.broadcast(); condition.unlock()
    }

    func checkpoint() throws {
        condition.lock()
        defer { condition.unlock() }
        while paused && !cancelled { condition.wait() }
        if cancelled { throw CancellationError() }
    }
}

package struct ImportReport: Codable, Sendable, Equatable {
    package struct Failure: Codable, Sendable, Equatable {
        package let path: String
        package let reason: String
    }

    package var finishedAt = Date()
    package var imported = 0
    package var alreadyPresent = 0
    package var duplicates: [String] = []
    package var sidecarsCopied = 0
    package var sidecarsExtracted = 0
    package var sidecarConflicts: [String] = []
    package var withoutMetadata: [String] = []
    package var unreadableMetadata: [String] = []
    package var editsApproximated = 0
    package var gpsOnlyInSidecar: [String] = []
    package var picksNotTransferred: [String] = []
    package var failures: [Failure] = []
    package var reportFile: String?

    package init() {}

    /// Photos that are in the destination folder after this run.
    package var available: Int { imported + alreadyPresent }
}

package struct ImportPlan: Sendable {
    package let sourceRoot: URL
    package let destinationRoot: URL
    package let photos: [ExportPhoto]

    package init(sourceRoot: URL, destinationRoot: URL, photos: [ExportPhoto]) {
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
        self.photos = photos
    }
}

/// Copies an export into a new folder. The source is only read, nothing that exists in the
/// destination is overwritten, and a file appears under its final name only after its copy
/// has been read back and matched against the original's SHA-256.
package enum ImportEngine {
    private static let chunkSize = 1024 * 1024

    package static func validate(source: URL, destination: URL) throws {
        let sourcePath = canonicalPath(source)
        let destinationPath = canonicalPath(destination)
        if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
            throw ImportValidationError.destinationInsideSource
        }
        if sourcePath.hasPrefix(destinationPath + "/") {
            throw ImportValidationError.sourceInsideDestination
        }
        var folder = URL(fileURLWithPath: destinationPath)
        while folder.path != "/" {
            let catalog = folder.appendingPathComponent("catalog.snap").path
            let lock = folder.appendingPathComponent("catalog.lock").path
            if FileManager.default.fileExists(atPath: catalog) || FileManager.default.fileExists(atPath: lock) {
                throw ImportValidationError.destinationIsLightCraftLibrary
            }
            folder.deleteLastPathComponent()
        }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Throws `CancellationError` when cancelled. Finished files stay in place, and a later
    /// run with the same folders recognises them and continues.
    @discardableResult
    package static func run(
        plan: ImportPlan,
        control: ImportControl = ImportControl(),
        onEvent: @escaping @Sendable (ImportEvent) -> Void = { _ in }
    ) throws -> ImportReport {
        guard !plan.photos.isEmpty else { throw ImportValidationError.noPhotos }
        try validate(source: plan.sourceRoot, destination: plan.destinationRoot)
        try FileManager.default.createDirectory(at: plan.destinationRoot, withIntermediateDirectories: true)

        var report = ImportReport()
        let total = plan.photos.count
        let totalBytes = max(1, plan.photos.reduce(Int64(0)) { $0 + $1.fileSize })
        let meter = Meter(total: total, onEvent: onEvent)

        // 1. Checksums and duplicates.
        onEvent(.stage(.hashing))
        onEvent(.log("\(total) Fotos werden geprüft"))
        var hashed: [(photo: ExportPhoto, hash: String)] = []
        var bytesRead: Int64 = 0
        for (index, photo) in plan.photos.enumerated() {
            try control.checkpoint()
            do {
                let hash = try sha256(of: photo.url, control: control) { count in
                    bytesRead += Int64(count)
                    meter.update(0.30 * Double(bytesRead) / Double(totalBytes), processed: index)
                }
                hashed.append((photo, hash))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.failures.append(.init(path: photo.id, reason: "Datei nicht lesbar"))
            }
        }
        let unique = removingDuplicates(hashed, report: &report)
        if !report.duplicates.isEmpty { onEvent(.log("\(report.duplicates.count) Duplikate übersprungen")) }

        // 2. Copy, read back, then give the file its final name.
        onEvent(.stage(.copying))
        var placed: [(photo: ExportPhoto, target: URL)] = []
        let uniqueBytes = max(1, unique.reduce(Int64(0)) { $0 + $1.photo.fileSize })
        var bytesCopied: Int64 = 0
        for (index, item) in unique.enumerated() {
            try control.checkpoint()
            let folder = item.photo.album.isEmpty
                ? plan.destinationRoot
                : plan.destinationRoot.appendingPathComponent(item.photo.album, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let slot = try targetSlot(for: item.photo, hash: item.hash, in: folder, control: control)
                if slot.exists {
                    report.alreadyPresent += 1
                } else {
                    try copy(item.photo.url, to: slot.url, expectedHash: item.hash, control: control) { count in
                        bytesCopied += Int64(count)
                        meter.update(0.30 + 0.60 * Double(bytesCopied) / Double(uniqueBytes * 2), processed: index)
                    }
                    report.imported += 1
                }
                placed.append((item.photo, slot.url))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.failures.append(.init(path: item.photo.id, reason: "Kopie fehlgeschlagen"))
            }
            meter.update(0.30 + 0.60 * Double(index + 1) / Double(unique.count), processed: index + 1)
        }
        onEvent(.log("\(report.imported) Originale kopiert und gegengeprüft"))
        if report.alreadyPresent > 0 { onEvent(.log("\(report.alreadyPresent) Fotos waren schon im Zielordner")) }

        // 3. Sidecars.
        onEvent(.stage(.sidecars))
        for (index, entry) in placed.enumerated() {
            try control.checkpoint()
            let photo = entry.photo
            do {
                if let sidecar = photo.sidecar {
                    let name = entry.target.lastPathComponent == photo.name
                        ? sidecar.lastPathComponent
                        : "\(entry.target.lastPathComponent).xmp"
                    switch try place(Data(contentsOf: sidecar), at: entry.target.deletingLastPathComponent().appendingPathComponent(name)) {
                    case .written: report.sidecarsCopied += 1
                    case .identical: break
                    case .conflict: report.sidecarConflicts.append(photo.id)
                    }
                } else if photo.needsExtractedSidecar, let packet = EmbeddedXMP.packet(in: photo.url) {
                    let url = entry.target.deletingLastPathComponent().appendingPathComponent("\(entry.target.lastPathComponent).xmp")
                    switch try place(packet, at: url) {
                    case .written: report.sidecarsExtracted += 1
                    case .identical: break
                    case .conflict: report.sidecarConflicts.append(photo.id)
                    }
                }
            } catch {
                report.failures.append(.init(path: photo.id, reason: "XMP nicht übernommen"))
            }
            if photo.xmpProblem {
                report.unreadableMetadata.append(photo.id)
            } else if photo.xmp == nil {
                report.withoutMetadata.append(photo.id)
            }
            if let xmp = photo.xmp, xmp.hasBasicAdjustments || xmp.hasCrop || xmp.hasMasks {
                report.editsApproximated += 1
            }
            if photo.gpsOnlyInSidecar { report.gpsOnlyInSidecar.append(photo.id) }
            if photo.xmp?.hasUnreadPick == true { report.picksNotTransferred.append(photo.id) }
            meter.update(0.90 + 0.08 * Double(index + 1) / Double(max(1, placed.count)), processed: total)
        }
        onEvent(.log("\(report.sidecarsCopied + report.sidecarsExtracted) XMP-Dateien übernommen"))

        // 4. Report.
        try control.checkpoint()
        onEvent(.stage(.report))
        report.finishedAt = Date()
        report.reportFile = try writeReport(report, to: plan.destinationRoot)
        meter.update(1, processed: total)
        onEvent(.log("Import abgeschlossen"))
        return report
    }

    /// Identical files count as duplicates only if no metadata would be lost: a copy with a
    /// sidecar wins over one without, and copies with different sidecars are all kept.
    private static func removingDuplicates(
        _ items: [(photo: ExportPhoto, hash: String)],
        report: inout ImportReport
    ) -> [(photo: ExportPhoto, hash: String)] {
        var keep = Set<Int>()
        for indices in Dictionary(grouping: items.indices, by: { items[$0].hash }).values {
            var bySidecar: [Data: Int] = [:]
            for index in indices {
                if let sidecar = items[index].photo.sidecar,
                   let data = try? Data(contentsOf: sidecar),
                   bySidecar[data] == nil {
                    bySidecar[data] = index
                }
            }
            if bySidecar.isEmpty, let first = indices.first {
                keep.insert(first)
            } else {
                keep.formUnion(bySidecar.values)
            }
        }
        var unique: [(photo: ExportPhoto, hash: String)] = []
        for (index, item) in items.enumerated() {
            if keep.contains(index) {
                unique.append(item)
            } else {
                report.duplicates.append(item.photo.id)
            }
        }
        return unique
    }

    package static func sha256(
        of url: URL,
        control: ImportControl? = nil,
        onBytes: (Int) -> Void = { _ in }
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try control?.checkpoint()
            let more: Bool = try autoreleasepool {
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { return false }
                hasher.update(data: chunk)
                onBytes(chunk.count)
                return true
            }
            if !more { break }
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The name this photo gets: its own, or `Name (2).ext` when another file already has it.
    private static func targetSlot(
        for photo: ExportPhoto, hash: String, in folder: URL, control: ImportControl
    ) throws -> (url: URL, exists: Bool) {
        let manager = FileManager.default
        let stem = (photo.name as NSString).deletingPathExtension
        let ext = (photo.name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(photo.name)
        var number = 2
        while true {
            if let attributes = try? manager.attributesOfItem(atPath: candidate.path) {
                if attributes[.type] as? FileAttributeType == .typeRegular,
                   (attributes[.size] as? NSNumber)?.int64Value == photo.fileSize,
                   try sha256(of: candidate, control: control) == hash {
                    return (candidate, true)
                }
            } else {
                return (candidate, false)
            }
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) (\(number))" : "\(stem) (\(number)).\(ext)")
            number += 1
        }
    }

    private static func copy(
        _ source: URL, to target: URL, expectedHash: String, control: ImportControl, onBytes: (Int) -> Void
    ) throws {
        let manager = FileManager.default
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        guard manager.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var finished = false
        defer { if !finished { try? manager.removeItem(at: temporary) } }

        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: temporary)
        var outputOpen = true
        defer { if outputOpen { try? output.close() } }

        var hasher = SHA256()
        while true {
            try control.checkpoint()
            let more: Bool = try autoreleasepool {
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { return false }
                hasher.update(data: chunk)
                try output.write(contentsOf: chunk)
                onBytes(chunk.count)
                return true
            }
            if !more { break }
        }
        try output.synchronize()
        try output.close()
        outputOpen = false

        guard hex(hasher.finalize()) == expectedHash,
              try sha256(of: temporary, control: control, onBytes: onBytes) == expectedHash else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let date = try? manager.attributesOfItem(atPath: source.path)[.modificationDate] as? Date {
            try? manager.setAttributes([.modificationDate: date], ofItemAtPath: temporary.path)
        }
        // Fails rather than replaces if the name was taken in the meantime.
        try manager.moveItem(at: temporary, to: target)
        finished = true
    }

    private enum Placement { case written, identical, conflict }

    private static func place(_ data: Data, at url: URL) throws -> Placement {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            let attributes = try manager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue == data.count else { return .conflict }
            return try Data(contentsOf: url) == data ? .identical : .conflict
        }
        try writeNew(data, to: url)
        return .written
    }

    private static func writeNew(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        try data.write(to: temporary, options: .withoutOverwriting)
        do {
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func writeReport(_ report: ImportReport, to folder: URL) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let stamp = formatter.string(from: report.finishedAt)
        var name = "Import-Bericht \(stamp).json"
        var number = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "Import-Bericht \(stamp) (\(number)).json"
            number += 1
        }
        var stored = report
        stored.reportFile = name
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try writeNew(encoder.encode(stored), to: folder.appendingPathComponent(name))
        return name
    }
}

/// Sends progress only when it moved visibly, so a large import doesn't flood the UI.
private final class Meter {
    private let total: Int
    private let onEvent: @Sendable (ImportEvent) -> Void
    private var last = -1.0
    private var lastProcessed = -1

    init(total: Int, onEvent: @escaping @Sendable (ImportEvent) -> Void) {
        self.total = total
        self.onEvent = onEvent
    }

    func update(_ fraction: Double, processed: Int) {
        let value = min(1, max(0, fraction))
        guard value - last >= 0.002 || processed != lastProcessed || value == 1 else { return }
        last = value
        lastProcessed = processed
        onEvent(.progress(fraction: value, processed: min(processed, total), total: total))
    }
}
