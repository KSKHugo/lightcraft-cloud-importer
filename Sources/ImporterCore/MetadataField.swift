import Foundation

package enum FieldStatus: String, CaseIterable, Sendable {
    /// LightCraft reads the field as it is.
    case direct
    /// Carried over, but the result can differ.
    case approximate
    /// No verified way into LightCraft yet.
    case open

    package var title: String {
        switch self {
        case .direct: "Direkt"
        case .approximate: "Angenähert"
        case .open: "Offen"
        }
    }
}

/// Every field the importer accounts for. The statuses follow LightCraft's XMP documentation
/// (`docs/xmp-interop.md`) and its sidecar reader.
package enum MetadataField: String, CaseIterable, Identifiable, Sendable {
    case rating, label, rejected, picked
    case title, caption, keywords, hierarchy, creator, copyright, altText
    case captureDate, gps, location, camera
    case albums, albumGroups, people
    case basicEdits, crop, masks, versions

    package var id: String { rawValue }

    package static let groups: [(title: String, fields: [MetadataField])] = [
        ("Bewertung und Auswahl", [.rating, .label, .rejected, .picked]),
        ("Beschreibung", [.title, .caption, .keywords, .hierarchy, .creator, .copyright, .altText]),
        ("Aufnahme und Ort", [.captureDate, .gps, .location, .camera]),
        ("Organisation", [.albums, .albumGroups, .people]),
        ("Bearbeitung", [.basicEdits, .crop, .masks, .versions])
    ]

    package var title: String {
        switch self {
        case .rating: "Sternebewertung"
        case .label: "Farbmarkierung"
        case .rejected: "Abgelehnt"
        case .picked: "Auswahl (Pick)"
        case .title: "Titel"
        case .caption: "Bildunterschrift"
        case .keywords: "Stichwörter"
        case .hierarchy: "Stichwort-Hierarchie"
        case .creator: "Urheber"
        case .copyright: "Copyright"
        case .altText: "Alt-Text"
        case .captureDate: "Aufnahmedatum"
        case .gps: "GPS-Position"
        case .location: "Ort, Region, Land"
        case .camera: "Kamera, Objektiv, Belichtung"
        case .albums: "Alben"
        case .albumGroups: "Album-Ordner"
        case .people: "Personen / Gesichter"
        case .basicEdits: "Grundeinstellungen"
        case .crop: "Zuschnitt"
        case .masks: "Masken und Retusche"
        case .versions: "Versionen und Verlauf"
        }
    }

    package var source: String {
        switch self {
        case .rating: "xmp:Rating"
        case .label: "xmp:Label"
        case .rejected: "xmp:Rating = -1"
        case .picked: "xmpDM:pick"
        case .title: "dc:title"
        case .caption: "dc:description"
        case .keywords: "dc:subject"
        case .hierarchy: "lr:hierarchicalSubject"
        case .creator: "dc:creator"
        case .copyright: "dc:rights"
        case .altText: "Iptc4xmpCore:AltTextAccessibility"
        case .captureDate: "exif:DateTimeOriginal"
        case .gps: "exif:GPSLatitude / Longitude"
        case .location: "photoshop:City / State / Country"
        case .camera: "EXIF im Original"
        case .albums, .albumGroups: "Export-Unterordner"
        case .people: "mwg-rs:Regions"
        case .basicEdits: "crs:Exposure2012 …"
        case .crop: "crs:HasCrop, crs:Crop…"
        case .masks: "crs:MaskGroupBasedCorrections …"
        case .versions: "nicht im Export"
        }
    }

    package var status: FieldStatus {
        switch self {
        case .picked, .versions: .open
        case .gps, .albums, .albumGroups, .basicEdits, .crop, .masks: .approximate
        default: .direct
        }
    }

    package var note: String {
        switch self {
        case .picked: "LightCraft liest dieses Feld nicht"
        case .gps: "Nur aus der Datei, nicht aus XMP"
        case .albums: "Werden zu Ordnern"
        case .albumGroups: "Werden zu Unterordnern"
        case .basicEdits: "Kann anders aussehen"
        case .crop: "Kann leicht abweichen"
        case .masks: "Kann deutlich abweichen"
        case .versions: "Quelle fehlt"
        default: ""
        }
    }

    /// Whether a photo carries this field; `nil` where the export does not tell.
    package func isPresent(in photo: ExportPhoto) -> Bool? {
        let xmp = photo.xmp
        switch self {
        case .rating: return (xmp?.rating ?? 0) > 0
        case .label: return xmp?.hasValue("xmp:Label") ?? false
        case .rejected: return xmp?.isRejected ?? false
        case .picked: return xmp?.hasUnreadPick ?? false
        case .title: return xmp?.hasValue("dc:title") ?? false
        case .caption: return xmp?.hasValue("dc:description") ?? false
        case .keywords: return xmp?.hasValue("dc:subject") ?? false
        case .hierarchy: return xmp?.hasValue("lr:hierarchicalSubject") ?? false
        case .creator: return xmp?.hasValue("dc:creator") ?? false
        case .copyright: return xmp?.hasValue("dc:rights") ?? false
        case .altText: return xmp?.hasValue("Iptc4xmpCore:AltTextAccessibility") ?? false
        case .captureDate:
            return ["exif:DateTimeOriginal", "photoshop:DateCreated", "xmp:CreateDate"]
                .contains { xmp?.hasValue($0) ?? false }
        case .gps: return xmp?.hasGPS ?? false
        case .location:
            return ["photoshop:City", "photoshop:State", "photoshop:Country", "Iptc4xmpCore:Location"]
                .contains { xmp?.hasValue($0) ?? false }
        case .albums: return !photo.album.isEmpty
        case .albumGroups: return photo.album.contains("/")
        case .people: return (xmp?.faceRegionCount ?? 0) > 0
        case .basicEdits: return xmp?.hasBasicAdjustments ?? false
        case .crop: return xmp?.hasCrop ?? false
        case .masks: return xmp?.hasMasks ?? false
        case .camera, .versions: return nil
        }
    }

    package static func coverage(of photos: [ExportPhoto]) -> [MetadataField: Int] {
        var counts: [MetadataField: Int] = [:]
        for field in allCases where field != .camera && field != .versions {
            counts[field] = photos.reduce(0) { $0 + (field.isPresent(in: $1) == true ? 1 : 0) }
        }
        return counts
    }
}
