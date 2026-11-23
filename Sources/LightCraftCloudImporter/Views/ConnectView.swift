import SwiftUI

struct ConnectView: View {
    @Bindable var model: AppModel

    private var sourceDetail: String {
        if model.isScanning { return "\(Format.count(model.scannedCount)) Fotos gelesen …" }
        if let library = model.library {
            return "\(Format.count(library.photos.count)) Fotos · \(Format.bytes(library.totalBytes))"
        }
        return "Noch nicht gewählt"
    }

    private var lightCraftDetail: String {
        if let version = model.lightCraftVersion { return "LightCraft \(version) gefunden" }
        return "LightCraft wurde nicht gefunden"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StepHeader(
                    title: "Ordner verbinden",
                    subtitle: "Der Export wird nur gelesen. Die Kopien landen in einem eigenen Ordner, den du danach in LightCraft importierst."
                )
                HStack(alignment: .top, spacing: 14) {
                    FolderCard(
                        heading: "Quelle",
                        symbol: "folder",
                        name: model.sourceURL?.lastPathComponent ?? "Lightroom-Export",
                        detail: sourceDetail,
                        problem: nil,
                        buttonTitle: model.sourceURL == nil ? "Wählen …" : "Ändern …",
                        isWorking: model.isScanning,
                        action: model.chooseSource
                    )
                    FolderCard(
                        heading: "Ziel",
                        symbol: "photo.stack",
                        name: model.destinationURL?.lastPathComponent ?? "Ordner für LightCraft",
                        detail: lightCraftDetail,
                        problem: model.destinationProblem,
                        buttonTitle: model.destinationURL == nil ? "Wählen …" : "Ändern …",
                        isWorking: false,
                        action: model.chooseDestination
                    )
                }
                Text("Wie sollen die Fotos übernommen werden?")
                    .font(.headline)
                    .padding(.top, 4)
                HStack(alignment: .top, spacing: 14) {
                    RouteCard(
                        title: "Originale mit Einstellungen",
                        text: "RAW-Dateien und Bearbeitungen bleiben erhalten. Exportiere dafür in Lightroom einmal „Original + Einstellungen“.",
                        isSelected: true
                    )
                    RouteCard(
                        title: "Vollautomatisch aus der Cloud",
                        text: "Nicht verfügbar. Adobe bietet keinen Download von Originalen, und der API-Zugang braucht eine Freigabe.",
                        isSelected: false
                    )
                    .opacity(0.6)
                }
                Notice(text: "Lege in Lightroom pro Album einen Unterordner an. Der Importer übernimmt diese Ordnerstruktur, denn der Export selbst enthält keine Alben.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FolderCard: View {
    let heading: String
    let symbol: String
    let name: String
    let detail: String
    let problem: String?
    let buttonTitle: String
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Button(buttonTitle, action: action)
                        .accessibilityLabel("\(heading): \(buttonTitle)")
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(6)
        } label: {
            Text(heading)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RouteCard: View {
    let title: String
    let text: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: isSelected ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
