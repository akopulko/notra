import Foundation
import Markdown

/// A single structured scope applied to sidebar search results.
enum NoteSearchFilter: String, CaseIterable, Identifiable, Sendable {
    case checklists
    case tags
    case attachments

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .checklists:
            "Notes with Checklists"
        case .tags:
            "Notes with Tags"
        case .attachments:
            "Notes with Attachments"
        }
    }

    var systemImage: String {
        switch self {
        case .checklists:
            "checklist"
        case .tags:
            "tag"
        case .attachments:
            "paperclip"
        }
    }

    nonisolated func matches(_ note: NoteSummary) -> Bool {
        switch self {
        case .checklists:
            note.hasChecklist
        case .tags:
            !note.tags.isEmpty
        case .attachments:
            note.attachmentSummary.showsPaperclip
        }
    }

    nonisolated static func hasChecklist(in markdown: String) -> Bool {
        containsChecklist(in: Document(parsing: markdown))
    }

    nonisolated static func hasLinkedAttachment(noteURL: URL, markdown: String) -> Bool {
        let assetsURL = noteURL.appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true)
        return MarkdownAttachmentReferences.linkedURLs(in: markdown, assetBaseURL: assetsURL)
            .contains { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    private nonisolated static func containsChecklist(in markup: any Markup) -> Bool {
        if let listItem = markup as? ListItem, listItem.checkbox != nil {
            return true
        }

        return markup.children.contains { containsChecklist(in: $0) }
    }
}
