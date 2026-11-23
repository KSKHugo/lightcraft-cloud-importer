import ImporterCore
import SwiftUI

private struct ReportIssue: Identifiable {
    let id: String
    let status: FieldStatus
    let title: String
    let text: String
    let count: Int
}

struct ReportView: View {
    @Bindable var model: AppModel

    private func issues(_ report: ImportReport) -> [ReportIssue] {
        let all = [
            ReportIssue(id: "failed", status: .open, title: "Nicht übernommen", text: "Diese Dateien konnten nicht gelesen oder kopiert werden. Die Details stehen im Bericht.", count: report.failures.count),
            ReportIssue(id: "conflict", status: .open, title: "Abweichende XMP-Datei im Ziel", text: "Im Zielordner lag schon eine andere XMP-Datei. Sie wurde nicht überschrieben.", count: report.sidecarConflicts.count),
            ReportIssue(id: "unreadable", status: .open, title: "XMP nicht lesbar", text: "Die Metadaten dieser Fotos ließen sich nicht auswerten.", count: report.unreadableMetadata.count),
            ReportIssue(id: "none", status: .open, title: "Keine XMP-Daten gefunden", text: "Das Original wurde kopiert, Bewertung und Stichwörter fehlen aber.", count: report.withoutMetadata.count),
            ReportIssue(id: "pick", status: .open, title: "Pick-Markierung", text: "LightCraft liest dieses Feld nicht. Die Markierung muss dort neu gesetzt werden.", count: report.picksNotTransferred.count),
            ReportIssue(id: "gps", status: .approximate, title: "GPS nur in XMP", text: "LightCraft liest GPS aus der Bilddatei, nicht aus XMP. Diese Fotos kommen ohne Position an.", count: report.gpsOnlyInSidecar.count),
            ReportIssue(id: "edits", status: .approximate, title: "Bearbeitungen angenähert", text: "Diese Fotos können in LightCraft anders aussehen als in Lightroom.", count: report.editsApproximated),
            ReportIssue(id: "verified", status: .direct, title: "Prüfsummen stimmen", text: "Jede Kopie im Zielordner ist identisch mit ihrem Original.", count: report.available)
        ]
        return all.filter { $0.count > 0 }
    }

    private func needsReview(_ report: ImportReport) -> Int {
        report.failures.count + report.sidecarConflicts.count + report.unreadableMetadata.count + report.withoutMetadata.count
            + report.picksNotTransferred.count + report.gpsOnlyInSidecar.count
    }

    var body: some View {
        ScrollView {
            if let report = model.report {
                VStack(alignment: .leading, spacing: 16) {
                    StepHeader(
                        title: "Bericht",
                        subtitle: "\(Format.count(report.available)) Fotos liegen bereit. Dein Lightroom-Export wurde nicht verändert."
                    )
                    HStack(spacing: 12) {
                        StatTile(title: "Neu kopiert", value: report.imported)
                        StatTile(title: "Schon vorhanden", value: report.alreadyPresent)
                        StatTile(title: "Duplikate", value: report.duplicates.count)
                        StatTile(title: "Bitte prüfen", value: needsReview(report))
                    }
                    Notice(
                        text: "Letzter Schritt: Importiere den Zielordner in LightCraft. Dabei liest LightCraft die XMP-Dateien automatisch.",
                        symbol: "arrow.right.circle"
                    )
                    GroupBox("Was du dir ansehen solltest") {
                        VStack(spacing: 0) {
                            let list = issues(report)
                            ForEach(list) { issue in
                                HStack(alignment: .firstTextBaseline, spacing: 11) {
                                    StatusBadge(status: issue.status)
                                        .frame(width: 92, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(issue.title).fontWeight(.semibold)
                                        Text(issue.text)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Text(Format.count(issue.count))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 8)
                                .accessibilityElement(children: .combine)
                                if issue.id != list.last?.id { Divider() }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    HStack {
                        if let file = report.reportFile {
                            Text(file)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Zielordner im Finder zeigen", action: model.revealDestination)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
