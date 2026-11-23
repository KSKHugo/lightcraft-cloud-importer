import Foundation

/// The file types LightCraft's import recognises (`EXTENSIONS` in its engine).
package enum PhotoFormats {
    package static let raw: Set<String> = [
        "dng", "cr2", "cr3", "nef", "nrw", "arw", "sr2", "srf", "raf", "orf", "rw2", "rwl",
        "raw", "pef", "srw", "iiq", "crw", "mrw", "x3f", "kdc", "mos", "erf", "3fr", "fff", "mef"
    ]

    package static let rendered: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "webp", "psd", "psb", "jxl", "gif", "bmp",
        "heic", "heif", "avif"
    ]

    package static func isPhoto(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return raw.contains(ext) || rendered.contains(ext)
    }

    package static func isRaw(_ url: URL) -> Bool {
        raw.contains(url.pathExtension.lowercased())
    }
}
