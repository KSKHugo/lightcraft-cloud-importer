import Foundation
import ImageIO

package struct ExportPhoto: Identifiable, Sendable, Equatable {
    /// Path relative to the export folder.
    package let id: String
    package let url: URL
    /// Relative folder; empty for photos directly in the export folder.
    package let album: String
    package let fileSize: Int64
    package let sidecar: URL?
    package let hasEmbeddedXMP: Bool
    package let xmp: XMPDocument?
    package let xmpProblem: Bool
    /// GPS stated only in a sidecar: LightCraft reads GPS from the file, not from sidecars.
    package let gpsOnlyInSidecar: Bool

    package var name: String { url.lastPathComponent }
    package var isRaw: Bool { PhotoFormats.isRaw(url) }

    /// LightCraft's import reads embedded XMP only from raw and DNG files. For other formats
    /// the packet has to be placed beside the copy as a sidecar.
    package var needsExtractedSidecar: Bool {
        sidecar == nil && hasEmbeddedXMP && !isRaw
    }
}

package struct ExportAlbum: Identifiable, Sendable, Equatable {
    package let id: String
    package let name: String
    package let group: String?
    package let count: Int
    package let bytes: Int64
}

package struct ExportLibrary: Sendable, Equatable {
    package let root: URL
    package let photos: [ExportPhoto]
    package let albums: [ExportAlbum]

    package var totalBytes: Int64 {
        photos.reduce(0) { $0 + $1.fileSize }
    }
}

package enum ExportScanner {
    /// Reads the export folder. Nothing is written. Hidden files, packages and symbolic links
    /// are skipped, so a link cannot pull files from outside the chosen folder into the import.
    package static func scan(
        root: URL,
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (Int) -> Void = { _ in }
    ) throws -> ExportLibrary {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw CocoaError(.fileReadNoPermission)
        }

        var photosByFolder: [String: [(url: URL, size: Int64)]] = [:]
        var sidecarsByFolder: [String: [String: URL]] = [:]
        let prefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"

        for case let url as URL in enumerator {
            if isCancelled() { throw CancellationError() }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            let folder = (relative as NSString).deletingLastPathComponent
            if url.pathExtension.lowercased() == "xmp" {
                sidecarsByFolder[folder, default: [:]][url.lastPathComponent.lowercased()] = url
            } else if PhotoFormats.isPhoto(url) {
                photosByFolder[folder, default: []].append((url, Int64(values.fileSize ?? 0)))
            }
        }

        var photos: [ExportPhoto] = []
        for folder in photosByFolder.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let files = photosByFolder[folder] ?? []
            let owners = stemOwners(files.map(\.url))
            let sidecars = sidecarsByFolder[folder] ?? [:]
            for file in files.sorted(by: { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }) {
                if isCancelled() { throw CancellationError() }
                let name = file.url.lastPathComponent
                let own = sidecars["\(name).xmp".lowercased()]
                let stem = (name as NSString).deletingPathExtension.lowercased()
                let shared = owners[stem] == name ? sidecars["\(stem).xmp"] : nil
                photos.append(readPhoto(
                    url: file.url,
                    id: folder.isEmpty ? name : "\(folder)/\(name)",
                    album: folder,
                    size: file.size,
                    sidecar: own ?? shared
                ))
                progress(photos.count)
            }
        }
        return ExportLibrary(root: resolvedRoot, photos: photos, albums: albums(from: photos))
    }

    /// Which file of a shared stem owns `<stem>.xmp`: a raw first, then the first by name,
    /// the same rule LightCraft applies on import.
    private static func stemOwners(_ urls: [URL]) -> [String: String] {
        var owners: [String: URL] = [:]
        for url in urls {
            let stem = url.deletingPathExtension().lastPathComponent.lowercased()
            guard let current = owners[stem] else { owners[stem] = url; continue }
            let currentRaw = PhotoFormats.isRaw(current), newRaw = PhotoFormats.isRaw(url)
            if newRaw != currentRaw {
                if newRaw { owners[stem] = url }
            } else if url.lastPathComponent < current.lastPathComponent {
                owners[stem] = url
            }
        }
        return owners.mapValues(\.lastPathComponent)
    }

    private static func readPhoto(url: URL, id: String, album: String, size: Int64, sidecar: URL?) -> ExportPhoto {
        var xmp: XMPDocument?
        var problem = false
        var embedded = false

        if let sidecar {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: sidecar.path)
                guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= XMPDocument.maximumSize else {
                    throw XMPError.tooLarge
                }
                xmp = try XMPDocument.parse(Data(contentsOf: sidecar))
            } catch {
                problem = true
            }
        } else if let packet = EmbeddedXMP.packet(in: url) {
            embedded = true
            do {
                xmp = try XMPDocument.parse(packet)
            } catch {
                problem = true
                embedded = false
            }
        }

        let gpsOnlyInSidecar = sidecar != nil && (xmp?.hasGPS ?? false) && !fileHasGPS(url)
        return ExportPhoto(
            id: id, url: url, album: album, fileSize: size, sidecar: sidecar,
            hasEmbeddedXMP: embedded, xmp: xmp, xmpProblem: problem, gpsOnlyInSidecar: gpsOnlyInSidecar
        )
    }

    private static func fileHasGPS(_ url: URL) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let gps = values[kCGImagePropertyGPSDictionary] as? [CFString: Any] else { return false }
        return gps[kCGImagePropertyGPSLatitude] != nil && gps[kCGImagePropertyGPSLongitude] != nil
    }

    private static func albums(from photos: [ExportPhoto]) -> [ExportAlbum] {
        Dictionary(grouping: photos, by: \.album)
            .map { folder, items in
                let parent = (folder as NSString).deletingLastPathComponent
                return ExportAlbum(
                    id: folder,
                    name: folder.isEmpty ? "Ohne Album" : (folder as NSString).lastPathComponent,
                    group: parent.isEmpty ? nil : parent,
                    count: items.count,
                    bytes: items.reduce(0) { $0 + $1.fileSize }
                )
            }
            .sorted { lhs, rhs in
                if lhs.id.isEmpty != rhs.id.isEmpty { return rhs.id.isEmpty }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }
}
