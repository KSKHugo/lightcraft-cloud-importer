import ImporterCore
import SwiftUI

struct ImportRunView: View {
    @Bindable var model: AppModel

    private var title: String {
        switch model.runState {
        case .idle: "Bereit zum Import"
        case .running: "Import läuft"
        case .paused: "Import pausiert"
        case .finished: "Import abgeschlossen"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: title,
                subtitle: "Du kannst jederzeit pausieren oder abbrechen. Beim nächsten Start erkennt der Importer fertige Kopien und macht dort weiter."
            )
            HStack(alignment: .top, spacing: 14) {
                GroupBox("Fortschritt") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(Format.count(model.processed)) von \(Format.count(model.selectedPhotos.count)) Fotos")
                            Spacer()
                            Text(Format.percent(model.fraction))
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        ProgressView(value: model.fraction)
                            .accessibilityLabel("Importfortschritt")
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(ImportStage.allCases) { stage in
                                stageRow(stage)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Protokoll") {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                if model.log.isEmpty {
                                    Text("Noch keine Einträge.")
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(model.log) { entry in
                                    Text("\(Format.time(entry.time))  \(entry.text)")
                                        .id(entry.id)
                                        .textSelection(.enabled)
                                }
                            }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                        }
                        .frame(height: 220)
                        .onChange(of: model.log.count) {
                            if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stageRow(_ stage: ImportStage) -> some View {
        let current = model.stage?.rawValue ?? -1
        let finished = model.runState == .finished || stage.rawValue < current
        let active = !finished && stage.rawValue == current && model.isRunActive
        return HStack(spacing: 9) {
            Group {
                if finished {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if active && model.runState == .running {
                    ProgressView().controlSize(.small)
                } else if active {
                    Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18, height: 18)
            Text(stage.title)
                .fontWeight(active ? .semibold : .regular)
                .foregroundStyle(finished || active ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
