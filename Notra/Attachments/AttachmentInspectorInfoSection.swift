import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Keeps statistics observation local so attachment rows do not reevaluate for each update.
struct AttachmentInspectorInfoSection: View {
    let store: NotesStore

    var body: some View {
        if let info = store.selectedNoteInfo {
            Section {
                #if os(macOS)
                NoteInfoView(info: info) {
                    NSWorkspace.shared.activateFileViewerSelecting([info.fileURL])
                }
                #else
                NoteInfoView(info: info)
                #endif
            } header: {
                Text("Note Info")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
    }
}
