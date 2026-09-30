import SwiftUI

/// Offers the six Markdown heading levels from one toolbar menu.
struct HeadingToolbarMenu: View {
    let action: (MarkdownHeadingLevel) -> Void
    let isEnabled: Bool

    var body: some View {
        Menu {
            ForEach(MarkdownHeadingLevel.allCases, id: \.self) { level in
                Button {
                    action(level)
                } label: {
                    Text(level.menuTitle)
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
        Button(action: action) {
            Label {
                Text(command.title)
            } icon: {
                Image(systemName: command.systemImage)
            }
        }
        .labelStyle(.iconOnly)
        .help(command.title)
        .accessibilityLabel(command.title)
        .disabled(!isEnabled)
    }
}

/// Keeps macOS heading, formatting, and attachment controls in one contiguous toolbar row.
struct MarkdownFormattingToolbar: ToolbarContent {
    let applyHeading: (MarkdownHeadingLevel) -> Void
    let applyFormatting: (NoteFormattingCommand) -> Void
    let isEnabled: Bool

    let attachFile: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 0) {
                HeadingToolbarMenu(action: applyHeading, isEnabled: isEnabled)
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)
                FormatToolbarButton(command: .bold, isEnabled: isEnabled) {
                    applyFormatting(.bold)
                }
                FormatToolbarButton(command: .italic, isEnabled: isEnabled) {
                    applyFormatting(.italic)
                }
                FormatToolbarButton(command: .strikethrough, isEnabled: isEnabled) {
                    applyFormatting(.strikethrough)
                }
                FormatToolbarButton(command: .quote, isEnabled: isEnabled) {
                    applyFormatting(.quote)
                }
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)
                FormatToolbarButton(command: .unorderedList, isEnabled: isEnabled) {
                    applyFormatting(.unorderedList)
                }
                FormatToolbarButton(command: .orderedList, isEnabled: isEnabled) {
                    applyFormatting(.orderedList)
                }
                FormatToolbarButton(command: .todo, isEnabled: isEnabled) {
                    applyFormatting(.todo)
                }
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)
                FormatToolbarButton(command: .link, isEnabled: isEnabled) {
                    applyFormatting(.link)
                }
                FormatToolbarButton(command: .table, isEnabled: isEnabled) {
                    applyFormatting(.table)
                }
                FormatToolbarButton(command: .code, isEnabled: isEnabled) {
                    applyFormatting(.code)
                }
                Button("Attach File", systemImage: "paperclip", action: attachFile)
                    .labelStyle(.iconOnly)
                    .help("Attach File")
                    .accessibilityLabel("Attach File")
                    .disabled(!isEnabled)
            }
        }
    }
}

extension MarkdownHeadingLevel {
    var menuTitle: LocalizedStringResource {
        switch self {
        case .h1:
            "# H1 Heading"
        case .h2:
            "## H2 Heading"
        case .h3:
            "### H3 Heading"
        case .h4:
            "#### H4 Heading"
        case .h5:
            "##### H5 Heading"
        case .h6:
            "###### H6 Heading"
        }
    }
}

extension NoteFormattingCommand {
    static let toolbarCommandGroups: [[NoteFormattingCommand]] = [
        [.bold, .italic, .strikethrough],
        [.unorderedList, .orderedList, .todo, .quote],
        [.link, .table, .code]
    ]

    static var editorMenuCommands: [NoteFormattingCommand] {
        #if os(iOS)
        toolbarCommandGroups.flatMap(\.self) + [.image]
        #else
        toolbarCommandGroups.flatMap(\.self)
        #endif
    }

    static var keyboardAccessoryCommands: [NoteFormattingCommand] {
        toolbarCommandGroups.flatMap(\.self)
    }

    var title: LocalizedStringResource {
        switch self {
        case .bold:
            "Bold"
        case .italic:
            "Italic"
        case .strikethrough:
            "Strikethrough"
        case .heading:
            "Headers"
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
        case .strikethrough:
            "strikethrough"
        case .heading:
            "textformat.size"
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

    var title: LocalizedStringResource {
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
