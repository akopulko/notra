import SwiftUI

struct NewNoteButton: View {
    let action: () -> Void

    var body: some View {
        Button("New Note", systemImage: "square.and.pencil", action: action)
            .labelStyle(.iconOnly)
            .help("New Note")
            .accessibilityLabel("New Note")
    }
}
