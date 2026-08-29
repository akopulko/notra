import Foundation

/// Stores the editor selection as UTF-16 offsets so UIKit and AppKit can share it.
struct MarkdownEditorSelectionSnapshot: Equatable {
    var lowerOffset = 0
    var upperOffset = 0

    var isEmpty: Bool {
        lowerOffset == upperOffset
    }

    func offsetDescription(in text: String) -> String {
        """
        offsets=\(lowerOffset)..<\(upperOffset); \
        isEmpty=\(isEmpty); textUTF16Length=\(text.utf16.count)
        """
    }
}

/// Retains the current and last useful non-empty selection across native editor callbacks.
final class MarkdownEditorSelectionStore {
    var snapshot = MarkdownEditorSelectionSnapshot()
    var lastNonEmptySnapshot: MarkdownEditorSelectionSnapshot?

    func record(_ newSnapshot: MarkdownEditorSelectionSnapshot) {
        guard newSnapshot != snapshot else {
            if !newSnapshot.isEmpty, lastNonEmptySnapshot != newSnapshot {
                lastNonEmptySnapshot = newSnapshot
            }
            return
        }

        snapshot = newSnapshot
        guard !newSnapshot.isEmpty else {
            return
        }
        lastNonEmptySnapshot = newSnapshot
    }
}
