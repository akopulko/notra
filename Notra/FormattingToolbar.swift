import SwiftUI

/// Offers the six Markdown heading levels from one toolbar menu.
struct HeadingToolbarMenu: View {
    let action: (MarkdownHeadingLevel) -> Void
    let isEnabled: Bool

    var body: some View {
        Menu {
            ForEach(MarkdownHeadingLevel.allCases, id: \.self) { level in
                Button(level.menuTitle) {
                    action(level)
                }
            }
        } label: {
            Image(systemName: NoteFormattingCommand.heading.systemImage)
        }
        .help(NoteFormattingCommand.heading.title)
        .accessibilityLabel(NoteFormattingCommand.heading.title)
        .disabled(!isEnabled)
    }
}

/// Renders one reusable formatting command with native help and accessibility text.
struct FormatToolbarButton: View {
    let command: NoteFormattingCommand
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(command.title, systemImage: command.systemImage, action: action)
            .labelStyle(.iconOnly)
            .help(command.title)
            .accessibilityLabel(command.title)
            .disabled(!isEnabled)
    }
}

/// Groups Markdown formatting controls in the order shared by the editor and app menus.
struct MarkdownFormattingToolbar: ToolbarContent {
    let applyHeading: (MarkdownHeadingLevel) -> Void
    let applyFormatting: (NoteFormattingCommand) -> Void
    let isEnabled: Bool

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            HeadingToolbarMenu(action: applyHeading, isEnabled: isEnabled)
            ForEach(NoteFormattingCommand.toolbarCommandGroups[0], id: \.self) { command in
                FormatToolbarButton(command: command, isEnabled: isEnabled) {
                    applyFormatting(command)
                }
            }
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup(placement: .primaryAction) {
            ForEach(NoteFormattingCommand.toolbarCommandGroups[1], id: \.self) { command in
                FormatToolbarButton(command: command, isEnabled: isEnabled) {
                    applyFormatting(command)
                }
            }
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup(placement: .primaryAction) {
            ForEach(NoteFormattingCommand.toolbarCommandGroups[2], id: \.self) { command in
                FormatToolbarButton(command: command, isEnabled: isEnabled) {
                    applyFormatting(command)
                }
            }
        }
    }
}

/// Exposes native undo and redo actions while reflecting bridge availability.
struct EditorUndoRedoToolbar: ToolbarContent {
    let availability: EditorUndoRedoAvailability
    let undo: () -> Void
    let redo: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .labelStyle(.iconOnly)
                .help("Undo")
                .accessibilityLabel("Undo")
                .disabled(!availability.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
                .labelStyle(.iconOnly)
                .help("Redo")
                .accessibilityLabel("Redo")
                .disabled(!availability.canRedo)
        }
    }
}

extension MarkdownHeadingLevel {
    var menuTitle: String {
        "\(markdownPrefix)h\(rawValue) Heading"
    }
}

extension NoteFormattingCommand {
    static let toolbarCommandGroups: [[NoteFormattingCommand]] = [
        [.hashtag, .bold, .italic],
        [.unorderedList, .orderedList, .todo, .quote],
        [.link, .table, .code]
    ]

    static var editorMenuCommands: [NoteFormattingCommand] {
        #if os(iOS)
        toolbarCommandGroups.flatMap(\.self).filter { $0 != .hashtag } + [.image]
        #else
        toolbarCommandGroups.flatMap(\.self)
        #endif
    }

    static var keyboardAccessoryCommands: [NoteFormattingCommand] {
        toolbarCommandGroups.flatMap(\.self)
    }

    var title: String {
        switch self {
        case .bold:
            "Bold"
        case .italic:
            "Italic"
        case .heading:
            "Headers"
        case .hashtag:
            "Hashtag"
        case .unorderedList:
            "Bulleted List"
        case .orderedList:
            "Numbered List"
        case .quote:
            "Quote"
        case .todo:
            "Checklist"
        case .code:
            "Code"
        case .link:
            "Link"
        case .table:
            "Table"
        case .image:
            "Image"
        }
    }

    var systemImage: String {
        switch self {
        case .bold:
            "bold"
        case .italic:
            "italic"
        case .heading:
            "textformat.size"
        case .hashtag:
            "number"
        case .unorderedList:
            "list.bullet"
        case .orderedList:
            "list.number"
        case .quote:
            "quote.opening"
        case .todo:
            "checklist"
        case .code:
            "chevron.left.forwardslash.chevron.right"
        case .link:
            "link"
        case .table:
            "tablecells"
        case .image:
            "photo"
        }
    }
}

/// The import actions grouped under the iOS keyboard accessory attachment menu.
enum AttachmentKeyboardMenuItem: CaseIterable, Hashable {
    case choosePhoto
    case attachFile

    var title: String {
        switch self {
        case .choosePhoto:
            "Choose Photo"
        case .attachFile:
            "Attach File"
        }
    }

    var systemImage: String {
        switch self {
        case .choosePhoto:
            "photo"
        case .attachFile:
            "doc"
        }
    }
}
