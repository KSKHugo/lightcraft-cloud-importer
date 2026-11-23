import Foundation

package enum XMPError: Error, Equatable {
    case tooLarge
    case forbiddenDeclaration
    case malformed
}

/// The top-level properties of an XMP packet, keyed by canonical name (`dc:title`), whatever
/// prefix the file happens to use. Only read: the importer never edits a packet.
package struct XMPDocument: Sendable, Equatable {
    package static let maximumSize = 32 * 1024 * 1024

    package let properties: [String: [String]]

    package init(properties: [String: [String]]) {
        self.properties = properties
    }

    /// Files come from outside the app: DTDs and entities are refused before parsing, so a
    /// crafted sidecar can neither expand endlessly nor reach for an external resource.
    package static func parse(_ data: Data) throws -> XMPDocument {
        guard data.count <= maximumSize else { throw XMPError.tooLarge }
        if data.range(of: Data("<!DOCTYPE".utf8)) != nil || data.range(of: Data("<!ENTITY".utf8)) != nil {
            throw XMPError.forbiddenDeclaration
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        let collector = Collector()
        parser.delegate = collector
        guard parser.parse() else { throw XMPError.malformed }
        return XMPDocument(properties: collector.properties)
    }

    package func contains(_ name: String) -> Bool {
        properties[name] != nil
    }

    package func value(_ name: String) -> String? {
        properties[name]?.first { !$0.isEmpty }
    }

    package func hasValue(_ name: String) -> Bool {
        value(name) != nil
    }

    package var rating: Int? {
        value("xmp:Rating").flatMap(Double.init).map { Int($0) }
    }

    package var isRejected: Bool {
        (rating ?? 0) < 0 || value("lc:flag") == "reject"
    }

    /// A pick that LightCraft would not see: `xmpDM:pick` is not one of the fields it reads.
    package var hasUnreadPick: Bool {
        value("xmpDM:pick") == "1" && value("lc:flag") == nil
    }

    package var hasGPS: Bool {
        hasValue("exif:GPSLatitude") && hasValue("exif:GPSLongitude")
    }

    package var hasBasicAdjustments: Bool {
        Self.basicAdjustments.contains { name in
            guard let text = value("crs:\(name)"), let number = Double(text) else { return false }
            return number != 0
        }
    }

    package var hasCrop: Bool {
        value("crs:HasCrop")?.lowercased() == "true"
    }

    package var hasMasks: Bool {
        Self.maskProperties.contains { contains("crs:\($0)") }
    }

    private static let basicAdjustments = [
        "Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012",
        "IncrementalTemperature", "IncrementalTint", "Texture", "Clarity2012", "Dehaze", "Vibrance", "Saturation"
    ]

    private static let maskProperties = [
        "MaskGroupBasedCorrections", "PaintBasedCorrections", "GradientBasedCorrections",
        "CircularGradientBasedCorrections", "RetouchAreas"
    ]
}

private final class Collector: NSObject, XMLParserDelegate {
    private static let canonicalPrefixes: [String: String] = [
        "adobe:ns:meta/": "x",
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#": "rdf",
        "http://ns.adobe.com/xap/1.0/": "xmp",
        "http://purl.org/dc/elements/1.1/": "dc",
        "http://ns.adobe.com/lightroom/1.0/": "lr",
        "http://ns.adobe.com/photoshop/1.0/": "photoshop",
        "http://ns.adobe.com/exif/1.0/": "exif",
        "http://ns.adobe.com/tiff/1.0/": "tiff",
        "http://ns.adobe.com/camera-raw-settings/1.0/": "crs",
        "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/": "Iptc4xmpCore",
        "http://www.metadataworkinggroup.com/schemas/regions/": "mwg-rs",
        "http://ns.adobe.com/xmp/1.0/DynamicMedia/": "xmpDM",
        "http://ns.lightcraft.app/lc/1.0/": "lc"
    ]

    private(set) var properties: [String: [String]] = [:]
    private var scopes: [[String: String]] = []
    private var path: [String] = []
    private var property: String?
    private var propertyDepth = 0
    private var text = ""
    private var sawItem = false

    private func canonical(_ qualifiedName: String) -> String {
        guard let colon = qualifiedName.firstIndex(of: ":") else { return qualifiedName }
        let prefix = String(qualifiedName[..<colon])
        let local = qualifiedName[qualifiedName.index(after: colon)...]
        for scope in scopes.reversed() {
            if let uri = scope[prefix] {
                return "\(Self.canonicalPrefixes[uri] ?? prefix):\(local)"
            }
        }
        return qualifiedName
    }

    private func add(_ value: String, to name: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        properties[name, default: []].append(contentsOf: trimmed.isEmpty ? [] : [trimmed])
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        var scope: [String: String] = [:]
        for (key, value) in attributeDict where key.hasPrefix("xmlns:") {
            scope[String(key.dropFirst(6))] = value
        }
        scopes.append(scope)
        let name = canonical(elementName)
        let parent = path.last
        path.append(name)

        if property == nil {
            if name == "rdf:Description", parent == "rdf:RDF" {
                for (key, value) in attributeDict where !key.hasPrefix("xmlns") {
                    let attribute = canonical(key)
                    if !attribute.hasPrefix("rdf:") { add(value, to: attribute) }
                }
            } else if parent == "rdf:Description" {
                property = name
                propertyDepth = path.count
                text = ""
                sawItem = false
                properties[name, default: []].append(contentsOf: [])
            }
        } else if name == "rdf:li" {
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if property != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = path.last
        if let property {
            if name == "rdf:li" {
                add(text, to: property)
                text = ""
                sawItem = true
            } else if path.count == propertyDepth {
                if !sawItem { add(text, to: property) }
                self.property = nil
            }
        }
        path.removeLast()
        scopes.removeLast()
    }
}

/// Finds the XMP packet embedded in a photo file, without decoding the image.
package enum EmbeddedXMP {
    private static let searchLimit = 16 * 1024 * 1024
    private static let opening = Data("<x:xmpmeta".utf8)
    private static let closing = Data("</x:xmpmeta>".utf8)

    package static func packet(in url: URL) -> Data? {
        guard let file = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        let window = file.startIndex..<(file.startIndex + min(file.count, searchLimit))
        guard let start = file.range(of: opening, in: window),
              let end = file.range(of: closing, in: start.upperBound..<window.upperBound),
              end.upperBound - start.lowerBound <= XMPDocument.maximumSize else { return nil }
        return Data(file[start.lowerBound..<end.upperBound])
    }
}
