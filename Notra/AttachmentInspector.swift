import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Shows note metadata, tags, and attached files while keeping selection actions platform-aware.
struct AttachmentInspectorView: View {
    let store: NotesStore
    let isEditing: Bool
    let insertAttachment: (TextBundleAsset) -> Void
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
                    sectionHeader("Note Info")
                }
            }

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
        #else
        let row = AttachmentRow(attachment: attachment)
            .tag(attachment.url)
            .onTapGesture(count: 2) {
                openAttachment(attachment)
            }
        #endif

        attachmentRowWithActions(row, attachment: attachment)
    }

    @ViewBuilder
    private func attachmentRowWithActions(
        _ row: some View,
        attachment: TextBundleAsset
    ) -> some View {
        if isEditing {
            row.contextMenu {
                attachmentActions(for: attachment)
            }
        } else {
            row
        }
    }

    @ViewBuilder
    private func attachmentActions(for attachment: TextBundleAsset) -> some View {
        Button("Insert", systemImage: "plus") {
            insertAttachment(attachment)
        }
        .disabled(attachment.isLinked)

        Button("Delete", systemImage: "trash", role: .destructive) {
            pendingDeletion = attachment
        }
    }

    private func openAttachment(_ attachment: TextBundleAsset) {
        guard attachment.kind == .attachment else {
            return
        }

        #if os(macOS)
        let didOpen = NSWorkspace.shared.open(attachment.url)
        if !didOpen {
            store.errorMessage = "The attachment could not be opened."
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
            return "This attachment is used in the note. All references to it will also be removed."
        }
        return "This permanently deletes the attachment from this note."
    }
}

/// Describes validation feedback kept beside the inspector's tag entry field.
private enum TagEntryFeedback {
    case invalid
    case duplicate

    var message: String {
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

/// Renders one attachment with its type-specific icon, preview action, and deletion affordance.
private struct AttachmentRow: View {
    let attachment: TextBundleAsset

    var body: some View {
        HStack(spacing: 12) {
            if attachment.kind == .image {
                AttachmentThumbnailView(url: attachment.url)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                AttachmentFileIconView()
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.filename)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Label(
                    attachment.isLinked ? "Linked" : "Not Linked",
                    systemImage: attachment.isLinked ? "link" : "link.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(attachment.isLinked ? "Linked" : "Not Linked")
    }
}

/// Chooses a familiar file icon for attachments that are not rendered as image thumbnails.
private struct AttachmentFileIconView: View {
    var body: some View {
        Image(systemName: "doc")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

/// Loads and displays an attachment thumbnail without making the inspector wait on disk I/O.
private struct AttachmentThumbnailView: View {
    @State private var image: Image?

    let url: URL

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .clipped()
        .task(id: url) {
            image = await loadImage()
        }
        .accessibilityHidden(true)
    }

    private func loadImage() async -> Image? {
        let imageURL = url
        let cgImage = await Task.detached(priority: .utility) {
            ImageThumbnailDecoder.decode(from: imageURL, maximumPixelSize: 192)
        }.value

        guard !Task.isCancelled, let cgImage else {
            return nil
        }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
