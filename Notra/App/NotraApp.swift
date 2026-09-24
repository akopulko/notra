import AppIntents
import SwiftUI

/// Provides a stable identity for reopening Notra's primary macOS window.
enum NotraWindowScene {
    static let mainID = "notra-main"
    static let primaryValue = "primary"
}

/// The application entry point, including the main window and platform settings scene.
@main
struct NotraApp: App {
    @State private var store = NotesStore()

    init() {
        AppLog.info("Launching Notra")
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup(id: NotraWindowScene.mainID, for: String.self) { _ in
            mainWindowContent
        } defaultValue: {
            NotraWindowScene.primaryValue
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            NotraCommands()
        }
        #else
        WindowGroup {
            mainWindowContent
        }
        .commands {
            NotraCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(store: store)
        }
        #endif
    }

    private var mainWindowContent: some View {
        ContentView(store: store)
            #if os(macOS)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbarBackground(.regularMaterial, for: .windowToolbar)
            .frame(minWidth: 720, minHeight: 480)
            #endif
    }
}
