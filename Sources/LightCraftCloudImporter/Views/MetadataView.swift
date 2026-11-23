import ImporterCore
import SwiftUI

struct MetadataView: View {
    @Bindable var model: AppModel

    private var visibleGroups: [(title: String, fields: [MetadataField])] {
        MetadataField.groups.compactMap { group in
            let fields = group.fields.filter { model.fieldFilter == nil || $0.status == model.fieldFilter }
            return fields.isEmpty ? nil : (group.title, fields)
        }
    }

    private func count(_ status: FieldStatus) -> Int {
        MetadataField.allCases.filter { $0.status == status }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(
                title: "Metadaten prüfen",
                subtitle: "So wird jedes Feld übernommen. „Direkt“ liest LightCraft unverändert, „Angenähert“ kann abweichen, „Offen“ lässt sich noch nicht übertragen."
            )
            Picker("Filter", selection: $model.fieldFilter) {
                Text("Alle \(MetadataField.allCases.count)").tag(FieldStatus?.none)
                ForEach(FieldStatus.allCases, id: \.self) { status in
                    Text("\(status.title) \(count(status))").tag(Optional(status))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)

            VStack(spacing: 0) {
                row(field: Text("Feld"), source: Text("Quelle"), amount: Text("Fotos"), status: AnyView(Text("Status")), note: Text("Hinweis"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
                List {
                    ForEach(visibleGroups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.fields) { field in
                                fieldRow(field)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(24)
    }

    private func fieldRow(_ field: MetadataField) -> some View {
        row(
            field: Text(field.title),
            source: Text(field.source).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary),
            amount: Text(amountText(field)).monospacedDigit().foregroundStyle(.secondary),
            status: AnyView(StatusBadge(status: field.status)),
            note: Text(field.note).font(.callout).foregroundStyle(.secondary)
        )
        .accessibilityElement(children: .combine)
    }

    private func amountText(_ field: MetadataField) -> String {
        guard let value = model.coverage[field] else { return "–" }
        return Format.count(value)
    }

    private func row(field: Text, source: Text, amount: Text, status: AnyView, note: Text) -> some View {
        HStack(spacing: 10) {
            field.lineLimit(1).frame(width: 190, alignment: .leading)
            source.lineLimit(1).truncationMode(.middle).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            amount.frame(width: 56, alignment: .trailing)
            status.frame(width: 92, alignment: .leading)
            note.lineLimit(1).frame(width: 200, alignment: .leading)
        }
    }
}
