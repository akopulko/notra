import Foundation

/// Stable UserDefaults keys for note creation preferences.
enum NoteSettingKey {
    static let startNewNoteWith = "notes.startNewNoteWith"
}

/// User-selectable templates for the initial Markdown written into newly created notes.
enum NoteStartContent: String, CaseIterable, Identifiable {
    case titleHeader
    case emptyNote

    static let defaultValue = NoteStartContent.titleHeader

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .titleHeader:
            "Title Header (#H1)"
        case .emptyNote:
            "Empty Note"
        }
    }

    var initialMarkdown: String {
        switch self {
        case .titleHeader:
            "# "
        case .emptyNote:
            ""
        }
    }

    static func resolved(rawValue: String) -> NoteStartContent {
        NoteStartContent(rawValue: rawValue) ?? defaultValue
    }
}
