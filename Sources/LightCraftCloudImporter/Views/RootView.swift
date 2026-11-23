import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    private var stepSelection: Binding<Step?> {
        Binding(
            get: { model.step },
            set: { if let target = $0 { model.go(to: target) } }
        )
    }

    private var showsError: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(Step.allCases, selection: stepSelection) { step in
                Label {
                    Text(step.title)
                } icon: {
                    Image(systemName: isDone(step) ? "checkmark.circle.fill" : step.symbol)
                        .foregroundStyle(isDone(step) ? Color.green : Color.accentColor)
                }
                .foregroundStyle(model.canOpen(step) ? .primary : .tertiary)
                .selectionDisabled(!model.canOpen(step))
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Format.count(model.selectedPhotos.count)) Fotos")
                        .fontWeight(.semibold)
                    Text("\(Format.bytes(model.selectedBytes)) ausgewählt")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch model.step {
                    case .connect: ConnectView(model: model)
                    case .pick: PickView(model: model)
                    case .metadata: MetadataView(model: model)
                    case .run: ImportRunView(model: model)
                    case .report: ReportView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                FooterBar(model: model)
            }
        }
        .navigationTitle("LightCraft Cloud Importer")
        .alert("Hinweis", isPresented: showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func isDone(_ step: Step) -> Bool {
        if step == .run { return model.runState == .finished }
        return step.rawValue < model.step.rawValue
    }
}

private struct FooterBar: View {
    @Bindable var model: AppModel

    private var summary: String {
        switch model.step {
        case .connect:
            if model.isScanning { return "Export wird gelesen …" }
            if model.sourceURL == nil { return "Wähle deinen Lightroom-Export." }
            if model.destinationURL == nil { return "Wähle einen Zielordner." }
            return model.destinationProblem ?? "Bereit für die Auswahl."
        case .pick:
            return "\(Format.count(model.selectedPhotos.count)) Fotos · \(Format.bytes(model.selectedBytes))"
        case .metadata:
            return "Nichts wird überschrieben. Der Export bleibt unverändert."
        case .run:
            return "\(Format.count(model.selectedPhotos.count)) Fotos in den Zielordner"
        case .report:
            return "Bericht im Zielordner gespeichert."
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            buttons
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var buttons: some View {
        switch model.step {
        case .connect:
            primary("Weiter", enabled: model.canOpen(.pick)) { model.advance() }
        case .pick:
            Button("Zurück") { model.goBack() }
            primary("Weiter", enabled: model.canOpen(.metadata)) { model.advance() }
        case .metadata:
            Button("Zurück") { model.goBack() }
            primary("Import vorbereiten", enabled: model.canOpen(.run)) { model.advance() }
        case .run:
            switch model.runState {
            case .idle:
                Button("Zurück") { model.goBack() }
                primary("Import starten", enabled: true) { model.startImport() }
            case .running, .paused:
                Button("Abbrechen", role: .destructive) { model.cancelImport() }
                primary(model.runState == .paused ? "Fortsetzen" : "Pausieren", enabled: true) { model.togglePause() }
            case .finished:
                primary("Bericht ansehen", enabled: true) { model.advance() }
            }
        case .report:
            Button("Neuer Import") { model.startOver() }
            primary("In LightCraft öffnen", enabled: model.lightCraftURL != nil) { model.openLightCraft() }
        }
    }

    private func primary(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
    }
}
