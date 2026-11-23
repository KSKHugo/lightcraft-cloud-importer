import AppKit
import ImporterCore
import SwiftUI

extension Color {
    /// The accent of the mockup: burnt orange, lighter in dark mode.
    static let importerAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.925, green: 0.569, blue: 0.376, alpha: 1)
            : NSColor(srgbRed: 0.690, green: 0.306, blue: 0.110, alpha: 1)
    })
}

enum Format {
    private static let locale = Locale(identifier: "de_DE")

    static func count(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file).locale(locale))
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second().locale(locale))
    }
}

extension FieldStatus {
    var color: Color {
        switch self {
        case .direct: .green
        case .approximate: .orange
        case .open: .secondary
        }
    }
}

struct StatusBadge: View {
    let status: FieldStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct Notice: View {
    let text: String
    var symbol = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatTile: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(Format.count(value))
                .font(.title.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .accessibilityElement(children: .combine)
    }
}

/// `CGImage` is immutable; the wrapper carries it from the loading task to the main actor.
private struct LoadedImage: @unchecked Sendable {
    let image: CGImage
}

private func loadThumbnail(_ url: URL) async -> LoadedImage? {
    await Task.detached(priority: .utility) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return LoadedImage(image: image)
    }.value
}

struct ThumbnailView: View {
    let photo: ExportPhoto
    @State private var image: NSImage?

    private var stars: String {
        String(repeating: "★", count: max(0, min(5, photo.xmp?.rating ?? 0)))
    }

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                HStack(spacing: 4) {
                    Text(photo.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(stars)
                        .fixedSize()
                }
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.top, 12)
                .padding(.bottom, 3)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stars.isEmpty ? photo.name : "\(photo.name), \(stars.count) Sterne")
            .task(id: photo.id) {
                if let loaded = await loadThumbnail(photo.url) {
                    image = NSImage(cgImage: loaded.image, size: .zero)
                }
            }
    }
}
