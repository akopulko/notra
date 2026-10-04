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
                    }
                }
            } header: {
                HStack {
                    Text("Tags")
                        .foregroundStyle(MarkdownTheme.preferred(for: colorScheme).previewHashtagColors.backgroundColor)
                    Spacer()
                    if tags.count > collapsedTagLimit {
                        Button {
                            showsAllTags.toggle()
                        } label: {
                            if showsAllTags {
                                Text(.showLess)
                            } else {
                                Text(.showAll)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notes.sidebar.tagVisibilityToggle")
                    }
                }
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
}
