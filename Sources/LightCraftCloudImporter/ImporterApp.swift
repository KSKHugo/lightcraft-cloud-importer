import AppKit
import SwiftUI

@main
struct LightCraftCloudImporterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("LightCraft Cloud Importer", id: "main") {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 640)
                .tint(.importerAccent)
                .task {
                    #if DEBUG
                    // `swift run` starts a bare executable, which is no regular app otherwise.
                    if Bundle.main.bundleIdentifier == nil {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate()
                    }
                    model.applyDebugArguments()
                    #endif
                }
        }
        .defaultSize(width: 1160, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
