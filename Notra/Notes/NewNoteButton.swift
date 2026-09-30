import SwiftUI

/// Renders the platform-appropriate control for creating a new note.
struct NewNoteButton: View {
    let action: () -> Void

    var body: some View {
        Button("New Note", systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .help("New Note")
            .accessibilityLabel("New Note")
    }

    private var systemImage: String {
        #if os(macOS)
        "plus"
        #else
        "square.and.pencil"
        #endif
    }
}
