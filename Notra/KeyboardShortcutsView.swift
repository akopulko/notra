import SwiftUI

/// Presents Notra's available keyboard commands with platform-adaptive key-cap styling.
struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                KeyboardShortcutsHeader()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(KeyboardShortcutSection.all) { section in
                        KeyboardShortcutSectionView(section: section)
                    }
                }

                Text("Press Escape to close this screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 760)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Keyboard Shortcuts")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}

private struct KeyboardShortcutsHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Work faster with Notra")
                .font(.title2.weight(.semibold))

            Text("Use these shortcuts whenever a hardware keyboard is connected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct KeyboardShortcutSectionView: View {
    let section: KeyboardShortcutSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(section.title)
                    .font(.headline)
            } icon: {
                Image(systemName: section.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 0) {
                ForEach(section.shortcuts) { shortcut in
                    KeyboardShortcutRow(shortcut: shortcut)

                    if shortcut.id != section.shortcuts.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(section.title)
    }
}

private struct KeyboardShortcutRow: View {
    let shortcut: KeyboardShortcut

    var body: some View {
        HStack(spacing: 12) {
            Text(shortcut.title)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(shortcut.keys) { key in
                    KeyboardKeyCap(key: key)
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct KeyboardKeyCap: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var minimumWidth = 28
    @ScaledMetric(relativeTo: .body) private var height = 30

    let key: KeyboardShortcutKey

    var body: some View {
        Text(verbatim: key.symbol)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(minWidth: minimumWidth, minHeight: height)
            .padding(.horizontal, 5)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.28 : 0.14))
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 1, y: 1)
            .accessibilityLabel(key.accessibilityLabel)
    }
}

private struct KeyboardShortcutSection: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let systemImage: String
    let shortcuts: [KeyboardShortcut]

    static let all = [
        KeyboardShortcutSection(
            id: "notes",
            title: "Notes",
            systemImage: "note.text",
            shortcuts: [
                KeyboardShortcut(id: "new-note", title: "New Note", keys: [.command, .letter("N")]),
                KeyboardShortcut(id: "delete-note", title: "Delete", keys: [.command, .delete]),
                KeyboardShortcut(
                    id: "toggle-preview", title: "Toggle Preview",
                    keys: [.command, .option, .letter("P")]
                )
            ]
        ),
        KeyboardShortcutSection(
            id: "formatting",
            title: "Formatting",
            systemImage: "textformat",
            shortcuts: [
                KeyboardShortcut(id: "heading-1", title: "Heading 1", keys: [.command, .option, .number("1")]),
                KeyboardShortcut(id: "heading-2", title: "Heading 2", keys: [.command, .option, .number("2")]),
                KeyboardShortcut(id: "heading-3", title: "Heading 3", keys: [.command, .option, .number("3")]),
                KeyboardShortcut(id: "heading-4", title: "Heading 4", keys: [.command, .option, .number("4")]),
                KeyboardShortcut(id: "heading-5", title: "Heading 5", keys: [.command, .option, .number("5")]),
                KeyboardShortcut(id: "heading-6", title: "Heading 6", keys: [.command, .option, .number("6")]),
                KeyboardShortcut(id: "bold", title: "Bold", keys: [.command, .letter("B")]),
                KeyboardShortcut(id: "italic", title: "Italic", keys: [.command, .letter("I")]),
                KeyboardShortcut(
                    id: "strikethrough", title: "Strikethrough",
                    keys: [.command, .shift, .letter("X")]
                )
            ]
        ),
        KeyboardShortcutSection(
            id: "blocks",
            title: "Blocks",
            systemImage: "list.bullet",
            shortcuts: [
                KeyboardShortcut(
                    id: "unordered-list", title: "Bullet List",
                    keys: [.command, .shift, .number("8")]
                ),
                KeyboardShortcut(
                    id: "ordered-list", title: "Numbered List",
                    keys: [.command, .shift, .number("7")]
                ),
                KeyboardShortcut(id: "todo", title: "To-Do", keys: [.command, .shift, .number("9")]),
                KeyboardShortcut(id: "quote", title: "Quote", keys: [.command, .shift, .letter("U")]),
                KeyboardShortcut(id: "code", title: "Code Block", keys: [.command, .option, .letter("C")])
            ]
        ),
        KeyboardShortcutSection(
            id: "insert",
            title: "Insert",
            systemImage: "plus.circle",
            shortcuts: [
                KeyboardShortcut(id: "link", title: "Link", keys: [.command, .letter("K")]),
                KeyboardShortcut(id: "table", title: "Table", keys: [.command, .option, .letter("T")])
            ]
        ),
        KeyboardShortcutSection(
            id: "help",
            title: "Help",
            systemImage: "questionmark.circle",
            shortcuts: [
                KeyboardShortcut(
                    id: "keyboard-shortcuts", title: "Keyboard Shortcuts",
                    keys: [.command, .character("/")]
                ),
                KeyboardShortcut(id: "close", title: "Close", keys: [.escape])
            ]
        )
    ]
}

private struct KeyboardShortcut: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let keys: [KeyboardShortcutKey]
}

private enum KeyboardShortcutKey: Identifiable {
    case command
    case option
    case shift
    case escape
    case delete
    case letter(String)
    case number(String)
    case character(String)
    var id: String {
        symbol
    }

    var symbol: String {
        switch self {
        case .command:
            "⌘"
        case .option:
            "⌥"
        case .shift:
            "⇧"
        case .escape:
            "esc"
        case .delete:
            "⌫"
        case let .letter(value), let .number(value), let .character(value):
            value
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .command:
            "Command"
        case .option:
            "Option"
        case .shift:
            "Shift"
        case .escape:
            "Escape"
        case .delete:
            "Delete"
        case let .letter(value), let .number(value), let .character(value):
            value
        }
    }
}

#Preview("Light") {
    NavigationStack {
        KeyboardShortcutsView()
    }
}

#Preview("Dark") {
    NavigationStack {
        KeyboardShortcutsView()
    }
    .preferredColorScheme(.dark)
}
