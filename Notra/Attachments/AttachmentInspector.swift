import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Shows note metadata, tags, and attached files while keeping selection actions platform-aware.
struct AttachmentInspectorView: View {
    let store: NotesStore
    let isEditing: Bool
    let linkAttachment: (TextBundleAsset) -> Void
    let unlinkAttachment: (TextBundleAsset) -> Void
    let removeTag: (NoteTag) -> Void
    @State private var selectedAttachmentURL: URL?
    @State private var pendingDeletion: TextBundleAsset?
    @State private var tagInput = ""
    @State private var tagEntryFeedback: TagEntryFeedback?
    #if os(iOS)
    @State private var previewedAttachment: AttachmentPreviewItem?
    #endif

    var body: some View {
        List(selection: $selectedAttachmentURL) {
            AttachmentInspectorInfoSection(store: store)

            tagSection

            if store.attachments.isEmpty {
                Section {
                    ContentUnavailableView("No Attachments", systemImage: "paperclip")
                        .listRowBackground(Color.clear)
                } header: {
                    sectionHeader("Attachments")
                }
            } else {
                assetSection(title: "Images", attachments: imageAttachments)
                assetSection(title: "Other Attachments", attachments: otherAttachments)
            }
        }
        #if os(macOS)
        .navigationTitle("Note Info")
        #else
        .sheet(item: $previewedAttachment) { item in
            AttachmentPreviewController(item: item)
        }
        #endif
        .confirmationDialog(
            "Delete Attachment?",
            isPresented: pendingDeletionBinding
        ) {
            Button("Delete", role: .destructive) {
                guard let attachment = pendingDeletion else {
                    return
                }
                pendingDeletion = nil
                Task {
                    await store.deleteAttachment(attachment)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(deletionMessage)
        }
        .onChange(of: store.attachments) {
            let selectionWasRemoved = selectedAttachmentURL.map { selectedURL in
                !store.attachments.contains { $0.url == selectedURL }
            } ?? false
            if selectionWasRemoved {
                selectedAttachmentURL = nil
            }
        }
        .onChange(of: store.selectedNoteID) {
            selectedAttachmentURL = nil
            pendingDeletion = nil
            tagInput = ""
            tagEntryFeedback = nil
        }
        .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
    }

    private var imageAttachments: [TextBundleAsset] {
        store.attachments.filter { $0.kind == .image }
    }

    private var otherAttachments: [TextBundleAsset] {
        store.attachments.filter { $0.kind == .attachment }
    }

    private var tagSection: some View {
        Section {
            tagEntry

            if store.selectedNoteTags.isEmpty {
                Text("No Tags")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(store.selectedNoteTags) { tag in
                        tagCapsule(for: tag)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
        } header: {
            sectionHeader("Tags")
        }
    }

    private var tagEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                tagInputField

                Button("Add Tag", systemImage: "plus") {
                    addTag()
                }
                .labelStyle(.iconOnly)
                .help("Add Tag")
                .accessibilityLabel("Add Tag")
                .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background, in: Capsule())

            if let tagEntryFeedback {
                Text(tagEntryFeedback.message)
                    .font(.caption)
                    .foregroundStyle(tagEntryFeedback.foregroundStyle)
                    .accessibilityLabel(tagEntryFeedback.message)
            }
        }
        .onChange(of: tagInput) {
            tagEntryFeedback = nil
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var tagInputField: some View {
        TextField("Add Tag", text: $tagInput)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
            .textFieldStyle(.plain)
            .onSubmit(addTag)
            .accessibilityLabel("Add Tag")
    }

    private func tagCapsule(for tag: NoteTag) -> some View {
        TagCapsule(
            tag: tag,
            size: .compact
        ) {
            removeTag(tag)
        }
        .frame(maxWidth: 180)
        .accessibilityAction(named: "Remove tag \(tag.displayName)") {
            removeTag(tag)
        }
    }

    private func addTag() {
        guard let tag = NoteTag(inspectorInput: tagInput) else {
            tagEntryFeedback = .invalid
            return
        }

        guard let result = store.addTag(tag) else {
            return
        }

        switch result {
        case .added:
            tagInput = ""
        case .duplicate:
            tagEntryFeedback = .duplicate
        }
    }

    @ViewBuilder
    private func assetSection(title: LocalizedStringKey, attachments: [TextBundleAsset]) -> some View {
        if !attachments.isEmpty {
            Section {
                attachmentGroup(title: "Linked", attachments: attachments.filter(\.isLinked))
                attachmentGroup(title: "Unlinked", attachments: attachments.filter { !$0.isLinked })
            } header: {
                sectionHeader(title)
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func attachmentGroup(title: LocalizedStringKey, attachments: [TextBundleAsset]) -> some View {
        if !attachments.isEmpty {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .listRowBackground(Color.clear)

            ForEach(attachments) { attachment in
                attachmentRow(for: attachment)
            }
        }
    }

    @ViewBuilder
    private func attachmentRow(for attachment: TextBundleAsset) -> some View {
        #if os(iOS)
        let row = Button {
            openAttachment(attachment)
        } label: {
            AttachmentRow(attachment: attachment)
        }
        .buttonStyle(.plain)
        .tag(attachment.url)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if attachment.isLinked {
                Button {
                    unlinkAttachment(attachment)
                } label: {
                    Label("Unlink", systemImage: "bolt.slash")
                }
            } else {
                Button {
                    linkAttachment(attachment)
                } label: {
                    Label("Link", systemImage: "bolt")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                pendingDeletion = attachment
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        #else
        let row = HStack(spacing: 12) {
            AttachmentRow(attachment: attachment)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    openAttachment(attachment)
                }

            VStack(spacing: 8) {
                if attachment.isLinked {
                    Button("Unlink", systemImage: "bolt.slash") {
                        unlinkAttachment(attachment)
                    }
                    .labelStyle(.iconOnly)
                    .help("Unlink")
                } else {
                    Button("Link", systemImage: "bolt") {
                        linkAttachment(attachment)
                    }
                    .labelStyle(.iconOnly)
                    .help("Link")
                }

                Button("Delete", systemImage: "trash") {
                    pendingDeletion = attachment
                }
                .labelStyle(.iconOnly)
                .help("Delete")
            }
        }
        .tag(attachment.url)
        #endif

        attachmentRowWithActions(row, attachment: attachment)
    }

    private func attachmentRowWithActions(
        _ row: some View,
        attachment: TextBundleAsset
    ) -> some View {
        row
            .contextMenu {
                attachmentActions(for: attachment)
                    .labelStyle(.titleAndIcon)
            }
    }

    @ViewBuilder
    private func attachmentActions(for attachment: TextBundleAsset) -> some View {
        if attachment.isLinked {
            Button {
                unlinkAttachment(attachment)
            } label: {
                Label("Unlink", systemImage: "bolt.slash")
            }
        } else {
            Button {
                linkAttachment(attachment)
            } label: {
                Label("Link", systemImage: "bolt")
            }
        }

        Button(role: .destructive) {
            pendingDeletion = attachment
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func openAttachment(_ attachment: TextBundleAsset) {
        // Open both images and other files through the platform's default preview or app.
        #if os(macOS)
        let didOpen = NSWorkspace.shared.open(attachment.url)
        if !didOpen {
            store.errorMessage = String(localized: "The attachment could not be opened.")
        }
        #else
        previewedAttachment = AttachmentPreviewItem(url: attachment.url)
        #endif
    }

    private var pendingDeletionBinding: Binding<Bool> {
        Binding {
            pendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                pendingDeletion = nil
            }
        }
    }

    private var deletionMessage: String {
        if pendingDeletion?.isLinked == true {
            return String(
                localized: "This attachment is used in the note. All references to it will also be removed."
            )
        }
        return String(localized: "This permanently deletes the attachment from this note.")
    }
}

/// Describes validation feedback kept beside the inspector's tag entry field.
private enum TagEntryFeedback {
    case invalid
    case duplicate

    var message: LocalizedStringResource {
        switch self {
        case .invalid:
            "Use letters, numbers, hyphens, or underscores."
        case .duplicate:
            "Tag already added."
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .invalid:
            .red
        case .duplicate:
            .secondary
        }
    }
}
