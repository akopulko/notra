import SwiftUI

#if os(iOS)
import PhotosUI
#endif

/// Coordinates the editor, live preview, formatting actions, attachments, tags, and note sharing.
struct NoteEditorPane: View {
    /// Main-actor store supplying the selected note and editor text.
    @Bindable var store: NotesStore
    /// Parent-owned edit/preview mode shared with the sidebar and floating button.
    @Binding var isEditing: Bool
    /// Repeated app-menu formatting actions forwarded to the native editor.
    let editorCommandRequest: NoteEditorCommandRequest?
    /// The split-view shell owns inspector presentation so native sidebar controls remain available.
    @Binding var isAttachmentInspectorPresented: Bool
    /// An existing asset selected for insertion in the shell's inspector.
    @Binding var attachmentToInsert: TextBundleAsset?
    /// Monotonic focus request emitted after creating a note.
    let editorFocusRequest: Int
    /// Monotonic focus request emitted by the preview-toggle keyboard command.
    let commandEditorFocusRequest: Int
    /// Parent callback used by the empty-selection create button.
    let createNote: () -> Void
    /// Monotonic request for inserting a newly imported local asset.
    let attachmentSelectionRequest: MarkdownAttachmentSelectionRequest
    /// Parent callback that presents the platform attachment picker.
    let requestAttachmentSelection: () -> Void
    /// Parent callback that exports the current note as a shareable PDF.
    let requestShare: () -> Void
    /// Current state of the shared PDF preparation flow.
    let shareState: NoteShareState
    /// Scene-owned native presenter anchoring PDF sharing to this editor's toolbar button.
    let sharePresenter: NoteSharePresenter
    /// Maximum accepted attachment size, shared with the Settings screen.
    @AppStorage(AttachmentSettingKey.maximumSizeMB) private var maximumAttachmentSizeMB =
        AttachmentSettings.defaultMaximumSizeMB
    /// Request counters let the native editor react to repeated identical commands.
    @State private var headingFormattingRequest = MarkdownHeadingFormattingRequest(id: 0, level: .h1)
    @State private var boldFormattingRequest = 0
    @State private var italicFormattingRequest = 0
    @State private var strikethroughFormattingRequest = 0
    @State private var codeFormattingRequest = 0
    @State private var mermaidFormattingRequest = 0
    @State private var linkFormattingRequest = 0
    @State private var tableFormattingRequest = 0
    @State private var imageFormattingRequest = MarkdownImageFormattingRequest(id: 0, source: "")
    @State private var attachmentFormattingRequest = MarkdownAttachmentFormattingRequest(
        id: 0,
        source: "",
        label: ""
    )
    @State private var linePrefixFormattingRequest = MarkdownLinePrefixFormattingRequest(
        id: 0,
        command: .unorderedList
    )
    /// Retains an unconsumed new-note focus request across the editor's first appearance only.
    @State private var pendingFocusFirstLineRequest = 0
    #if os(iOS)
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var isImagePickerPresented = false
    #endif

    var body: some View {
        Group {
            if store.hasSelection {
                if isEditing {
                    editor
                } else {
                    preview
                }
            } else {
                noSelectionContent
            }
        }
        #if os(iOS)
        .modifier(imagePickerPresentationModifier)
        #endif
        .onChange(of: attachmentSelectionRequest) {
            importAttachmentFromSelectionRequest()
        }
        .onChange(of: editorCommandRequest) {
            handleEditorCommandRequest()
        }
        .onChange(of: attachmentToInsert) {
            guard let attachment = attachmentToInsert else {
                return
            }
            attachmentToInsert = nil
            insertAttachment(attachment)
        }
        .onChange(of: store.selectedNoteID) {
            isEditing = false
            pendingFocusFirstLineRequest = 0
        }
        .onChange(of: editorFocusRequest) {
            if editorFocusRequest > 0 {
                pendingFocusFirstLineRequest = editorFocusRequest
                isEditing = true
            }
        }
        .toolbar {
            editorToolbar
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: Binding {
                store.editorText
            } set: { newValue in
                store.updateEditorText(newValue)
            },
            applyFormattingCommand: handleFormattingCommand,
            applyHeading: handleHeading,
            requestAttachmentSelection: presentAttachmentPicker,
            headingFormattingRequest: headingFormattingRequest,
            boldFormattingRequest: boldFormattingRequest,
            italicFormattingRequest: italicFormattingRequest,
            strikethroughFormattingRequest: strikethroughFormattingRequest,
            codeFormattingRequest: codeFormattingRequest,
            mermaidFormattingRequest: mermaidFormattingRequest,
            linkFormattingRequest: linkFormattingRequest,
            tableFormattingRequest: tableFormattingRequest,
            imageFormattingRequest: imageFormattingRequest,
            attachmentFormattingRequest: attachmentFormattingRequest,
            linePrefixFormattingRequest: linePrefixFormattingRequest,
            focusFirstLineRequest: pendingFocusFirstLineRequest,
            focusEditorRequest: commandEditorFocusRequest,
            onFocusFirstLineHandled: consumeFocusFirstLineRequest
        )
    }

    private var preview: some View {
        MarkdownPreview(
            markdown: store.editorText,
            context: .textBundle(noteURL: store.selectedNoteURL),
            tags: store.selectedNoteTags,
            attachments: PreviewAttachmentOverlayModel.linkedNonImageAttachments(
                from: store.attachments,
                markdown: store.editorText,
                noteURL: store.selectedNoteURL
            ),
            toggleTask: store.toggleTask
        )
    }

    private func consumeFocusFirstLineRequest() {
        pendingFocusFirstLineRequest = 0
    }

    private var noSelectionContent: some View {
        ContentUnavailableView(
            "Select a Note",
            systemImage: "square.and.pencil",
            description: Text("Choose a note or create a new one.")
        )
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            editToolbarButton
        }
        MarkdownFormattingToolbar(
            applyHeading: handleHeading,
            applyFormatting: handleFormattingCommand,
            isEnabled: store.hasSelection && isEditing,
            attachFile: presentAttachmentPicker
        )
        ToolbarItemGroup(placement: .primaryAction) {
            shareToolbarButton
            inspectorToolbarButton
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            editToolbarButton
        }
        ToolbarItem(placement: .primaryAction) {
            shareToolbarButton
        }
        ToolbarItem(placement: .primaryAction) {
            inspectorToolbarButton
        }
        #endif
    }

    private var editToolbarButton: some View {
        Button {
            isEditing.toggle()
        } label: {
            Image(systemName: isEditing ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isEditing ? Color.accentColor : Color.primary)
        }
        .help(isEditing ? "Done" : "Edit")
        .accessibilityLabel(isEditing ? "Done" : "Edit")
        .disabled(!store.hasSelection)
    }

    private var shareToolbarButton: some View {
        Button(shareButtonTitle, systemImage: shareButtonSymbol) {
            guard case .generating = shareState else {
                requestShare()
                return
            }
        }
        .labelStyle(.iconOnly)
        .help(shareButtonHelp)
        .accessibilityLabel(shareButtonHelp)
        .disabled(isPreparingShare || !canShare)
        #if os(macOS)
        .background {
            NoteShareAnchorView(presenter: sharePresenter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #endif
    }

    private var shareButtonTitle: LocalizedStringKey {
        switch shareState {
        case .idle:
            "share"
        case .failed:
            "Retry Share"
        case .generating:
            "Preparing Share"
        }
    }

    private var shareButtonSymbol: String {
        switch shareState {
        case .idle, .generating:
            "square.and.arrow.up"
        case .failed:
            "arrow.clockwise"
        }
    }

    private var shareButtonHelp: LocalizedStringKey {
        switch shareState {
        case .idle:
            "Share"
        case .failed:
            "Retry Share"
        case .generating:
            "Preparing PDF to share"
        }
    }

    private var isPreparingShare: Bool {
        if case .generating = shareState {
            return true
        }
        return false
    }

    private var inspectorToolbarButton: some View {
        Button {
            isAttachmentInspectorPresented.toggle()
        } label: {
            Image(systemName: isAttachmentInspectorPresented ? "info.circle.fill" : "info")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isAttachmentInspectorPresented ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("Attachments")
        .help("Attachments")
        .disabled(!store.hasSelection)
    }

    #if os(iOS)
    private var imagePickerPresentationModifier: ImagePickerPresentationModifier {
        ImagePickerPresentationModifier(
            isPresented: $isImagePickerPresented,
            selection: $selectedImageItem
        ) { item in
            Task {
                await importImage(from: item)
            }
        }
    }
    #endif
}

private extension NoteEditorPane {
    private var canShare: Bool {
        !isEditing && store.hasSelection
    }

    private func insertAttachment(_ attachment: TextBundleAsset) {
        guard !attachment.isLinked else {
            return
        }

        isEditing = true
        Task { @MainActor in
            insertMarkdownReference(
                for: attachment.kind,
                source: attachment.markdownSource,
                label: attachment.filename
            )
        }
    }

    private func handleHeading(_ level: MarkdownHeadingLevel) {
        headingFormattingRequest = MarkdownHeadingFormattingRequest(
            id: headingFormattingRequest.id + 1,
            level: level
        )
    }

    private func handleFormattingCommand(_ command: NoteFormattingCommand) {
        switch command {
        case .bold:
            boldFormattingRequest += 1
        case .italic:
            italicFormattingRequest += 1
        case .strikethrough:
            strikethroughFormattingRequest += 1
        case .code:
            codeFormattingRequest += 1
        case .mermaid:
            mermaidFormattingRequest += 1
        case .link:
            linkFormattingRequest += 1
        case .table:
            tableFormattingRequest += 1
        case .image:
            AppLog.info(
                """
                Image toolbar button tapped; \
                hasSelection=\(store.hasSelection); isEditing=\(isEditing)
                """
            )
            presentImagePicker()
        case .unorderedList, .orderedList, .quote, .todo:
            linePrefixFormattingRequest = MarkdownLinePrefixFormattingRequest(
                id: linePrefixFormattingRequest.id + 1,
                command: command
            )
        case .heading:
            break
        }
    }

    private func handleEditorCommandRequest() {
        guard let editorCommandRequest else {
            return
        }

        switch editorCommandRequest.command {
        case let .heading(level):
            handleHeading(level)
        case let .formatting(command):
            handleFormattingCommand(command)
        }
    }

    private func presentImagePicker() {
        #if os(iOS)
        AppLog.info("Presenting image photo picker")
        isImagePickerPresented = true
        #else
        AppLog.info("Requesting attachment file importer presentation from image command")
        requestAttachmentSelection()
        #endif
    }

    private func presentAttachmentPicker() {
        AppLog.info(
            """
            Attachment toolbar button tapped; \
            hasSelection=\(store.hasSelection); isEditing=\(isEditing)
            """
        )
        requestAttachmentSelection()
    }

    #if os(iOS)
    private func importImage(from item: PhotosPickerItem) async {
        defer { selectedImageItem = nil }

        do {
            AppLog.info("Loading selected photo picker image data")
            guard let data = try await item.loadTransferable(type: Data.self) else {
                AppLog.warning("Photo picker returned no image data")
                return
            }
            AppLog.info("Loaded photo picker image data; bytes=\(data.count)")
            let importedAsset = try store.importImage(
                data: data,
                originalFilename: "image",
                maximumByteCount: maximumAttachmentByteCount
            )
            insertMarkdownReference(
                for: importedAsset.kind,
                source: importedAsset.source,
                label: importedAsset.filename
            )
            AppLog.info("Queued image markdown insertion; source=\(importedAsset.source)")
        } catch {
            AppLog.error("Failed to import photo picker image: \(error.localizedDescription)")
            store.errorMessage = error.localizedDescription
        }
    }
    #endif

    private func importAttachmentFromSelectionRequest() {
        guard let url = attachmentSelectionRequest.url else {
            return
        }

        AppLog.info(
            """
            Handling attachment file importer selection; \
            requestID=\(attachmentSelectionRequest.id); name=\(url.lastPathComponent)
            """
        )
        importAttachment(from: url)
    }

    private func importAttachment(from url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        AppLog.debug("Security-scoped attachment access started=\(didStartAccessing)")
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
                AppLog.debug("Security-scoped attachment access stopped")
            }
        }

        do {
            let importedAsset = try store.importAttachment(
                from: url,
                maximumByteCount: maximumAttachmentByteCount
            )
            insertMarkdownReference(
                for: importedAsset.kind,
                source: importedAsset.source,
                label: importedAsset.filename
            )
            AppLog.info("Queued attachment markdown insertion; source=\(importedAsset.source)")
        } catch {
            AppLog.error("Failed to import attachment file: \(error.localizedDescription)")
            store.errorMessage = error.localizedDescription
        }
    }

    private var maximumAttachmentByteCount: Int64 {
        AttachmentSettings.maximumSizeBytes(for: maximumAttachmentSizeMB)
    }

    private func insertMarkdownReference(
        for kind: TextBundleAssetKind,
        source: String,
        label: String
    ) {
        switch kind {
        case .image:
            imageFormattingRequest = MarkdownImageFormattingRequest(
                id: imageFormattingRequest.id + 1,
                source: source
            )
        case .attachment:
            attachmentFormattingRequest = MarkdownAttachmentFormattingRequest(
                id: attachmentFormattingRequest.id + 1,
                source: source,
                label: label
            )
        }
    }
}
