import AppIntents
import SwiftUI

/// The application entry point, including the main window and platform settings scene.
@main
struct NotraApp: App {
    @State private var store = NotesStore()

    init() {
        AppLog.info("Launching Notra")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
            #if os(macOS)
                .frame(minWidth: 720, minHeight: 480)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
