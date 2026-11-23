// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LightCraftCloudImporter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LightCraftCloudImporter", targets: ["LightCraftCloudImporter"]),
        // Exposed so the core can be built and tested on its own (`swift test`).
        .library(name: "ImporterCore", targets: ["ImporterCore"])
    ],
    // No third-party dependencies and no network code: photos never leave the Mac.
    targets: [
        // Everything without a UI: scanning an export, reading XMP, the safe copy.
        // Declarations use the `package` access level.
        .target(
            name: "ImporterCore",
            path: "Sources/ImporterCore"
        ),
        // The SwiftUI app.
        .executableTarget(
            name: "LightCraftCloudImporter",
            dependencies: ["ImporterCore"],
            path: "Sources/LightCraftCloudImporter"
        ),
        .testTarget(
            name: "ImporterCoreTests",
            dependencies: ["ImporterCore"],
            path: "Tests/ImporterCoreTests"
        )
    ]
)
