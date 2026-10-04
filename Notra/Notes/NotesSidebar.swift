import SwiftUI

/// Provides library-wide tag filters independently from the notes content list.
struct NotesSidebar: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var showsAllTags = false

    private let collapsedTagLimit = 10
    private let expandedTagLimit = 100

    let tags: [NoteTag]
    let selectedTagIDs: Set<String>
    let isDisabled: Bool
    let showAllNotes: () -> Void
    let toggleTag: (NoteTag) -> Void

    private var visibleTags: ArraySlice<NoteTag> {
        tags.prefix(showsAllTags ? expandedTagLimit : collapsedTagLimit)
    }

    var body: some View {
        List {
            Section {
                Button(action: showAllNotes) {
                    Label(.allNotes, systemImage: "note.text")
                }
                .accessibilityIdentifier("notes.sidebar.allNotes")
                .accessibilityAddTraits(selectedTagIDs.isEmpty ? .isSelected : [])
            }

            Section {
                if tags.isEmpty {
                    Text("No Tags")
                        .foregroundStyle(.secondary)
                } else {
                    TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(visibleTags) { tag in
                            tagButton(tag)
                        }
                        if !showsAllTags, tags.count > collapsedTagLimit {
                            showAllTagsButton
                        }
                    }
                }
            } header: {
                Text("Tags")
                    .foregroundStyle(MarkdownTheme.preferred(for: colorScheme).previewHashtagColors.backgroundColor)
            }
        }
        .listStyle(.sidebar)
        .disabled(isDisabled)
        .accessibilityIdentifier("notes.sidebar")
    }

    private func tagButton(_ tag: NoteTag) -> some View {
        let isSelected = selectedTagIDs.contains(tag.id)
        return Button {
            toggleTag(tag)
        } label: {
            TagCapsule(tag: tag, size: .regular, style: .sidebar)
                .opacity(isSelected ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notes.sidebar.tag.\(tag.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var showAllTagsButton: some View {
        Button {
            showsAllTags = true
        } label: {
            Text(verbatim: "...")
                .modifier(TagCapsuleAppearance(size: .regular, style: .sidebar))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notes.sidebar.showAllTags")
        .accessibilityLabel(Text(.showAllTags))
    }
}
