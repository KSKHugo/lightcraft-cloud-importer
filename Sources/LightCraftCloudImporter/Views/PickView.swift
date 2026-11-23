import ImporterCore
import SwiftUI

struct PickView: View {
    @Bindable var model: AppModel

    private static let previewLimit = 120

    private var albumGroups: [(title: String, albums: [ExportAlbum])] {
        let albums = model.library?.albums ?? []
        let named = Dictionary(grouping: albums.filter { $0.group != nil }) { $0.group ?? "" }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { (title: $0.key, albums: $0.value) }
        let rest = albums.filter { $0.group == nil }
        return named + (rest.isEmpty ? [] : [(title: named.isEmpty ? "Alben" : "Weitere", albums: rest)])
    }

    private var allSelected: Bool {
        model.selectedAlbums.count == (model.library?.albums.count ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(
                title: "Fotos wählen",
                subtitle: "Wähle ganze Alben oder alles. Fotos, die schon im Zielordner liegen, erkennt der Importer und überspringt sie."
            )
            .padding([.horizontal, .top], 24)

            HStack(alignment: .top, spacing: 14) {
                GroupBox {
                    List {
                        ForEach(albumGroups, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.albums) { album in
                                    albumRow(album)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } label: {
                    HStack {
                        Text("Alben")
                        Spacer()
                        Button(allSelected ? "Keine" : "Alle", action: model.toggleAllAlbums)
                            .controlSize(.small)
                    }
                }
                .frame(width: 280)

                photoGrid
            }
            .padding([.horizontal, .bottom], 24)
        }
    }

    private func albumRow(_ album: ExportAlbum) -> some View {
        Toggle(isOn: Binding(
            get: { model.isSelected(album) },
            set: { model.setSelected(album, $0) }
        )) {
            HStack {
                Text(album.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(Format.count(album.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
    }

    @ViewBuilder
    private var photoGrid: some View {
        if model.selectedPhotos.isEmpty {
            ContentUnavailableView("Keine Fotos gewählt", systemImage: "photo.on.rectangle", description: Text("Wähle links mindestens ein Album."))
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(model.selectedPhotos.prefix(Self.previewLimit)) { photo in
                        ThumbnailView(photo: photo)
                    }
                }
                if model.selectedPhotos.count > Self.previewLimit {
                    Text("Vorschau der ersten \(Self.previewLimit) von \(Format.count(model.selectedPhotos.count)) Fotos")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                }
            }
        }
    }
}
