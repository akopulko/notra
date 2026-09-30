import SwiftUI

/// Renders the shared plus-icon control for creating a new note.
struct NewNoteButton: View {
    let action: () -> Void

    var body: some View {
        Button("New Note", systemImage: "plus", action: action)
            .labelStyle(.iconOnly)
            .help("New Note")
            .accessibilityLabel("New Note")
    }
}
