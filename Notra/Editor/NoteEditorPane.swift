import SwiftUI

#if os(iOS)
import PhotosUI
#endif

/// Coordinates the editor, live preview, formatting actions, attachments, tags, and note sharing.
struct NoteEditorPane: View {
    /// Keeps animated feedback respectful of the user's accessibility preference.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives syntax colors and Markdown preview palette selection.
    @Environment(\.colorScheme) private var colorScheme
    /// Main-actor store supplying the selected note and editor text.
    @Bindable var store: NotesStore
    /// Parent-owned edit/preview mode shared with the sidebar and floating button.
    @Binding var isEditing: Bool
    /// Monotonic focus request emitted after creating a note.
    let editorFocusRequest: Int
    /// Parent callback used by the empty-selection create button.
    let createNote: () -> Void
    /// Monotonic request for inserting a newly imported local asset.
    let attachmentSelectionRequest: MarkdownAttachmentSelectionRequest
    /// Parent callback that presents the platform attachment picker.
    let requestAttachmentSelection: () -> Void
    /// Maximum accepted attachment size, shared with the Settings screen.
    @AppStorage(AttachmentSettingKey.maximumSizeMB) private var maximumAttachmentSizeMB =
        AttachmentSettings.defaultMaximumSizeMB
    /// Persisted preview font family.
    @AppStorage(AppearanceSettingKey.previewFontName) private var previewFontName = AppearanceFont.defaultName
    /// Whether preview code should use the editor's selected syntax theme.
    @AppStorage(AppearanceSettingKey.previewUsesEditorTheme) private var previewUsesEditorTheme = true
    /// Request counters let the native editor react to repeated identical commands.
    @State private var headingFormattingRequest = MarkdownHeadingFormattingRequest(id: 0, level: .h1)
    @State private var boldFormattingRequest = 0
    @State private var italicFormattingRequest = 0
    @State private var codeFormattingRequest = 0
    @State private var linkFormattingRequest = 0
    @State private var tableFormattingRequest = 0
    @State private var imageFormattingRequest = MarkdownImageFormattingRequest(id: 0, source: "")
    @State private var attachmentFormattingRequest = MarkdownAttachmentFormattingRequest(
        id: 0,
        source: "",
        label: ""
    )
    @State private var undoRequest = 0
    @State private var redoRequest = 0
    @State private var undoRedoAvailability = EditorUndoRedoAvailability.disabled
    @State private var linePrefixFormattingRequest = MarkdownLinePrefixFormattingRequest(
        id: 0,
        command: .unorderedList
    )
    @State private var isAttachmentInspectorPresented = false
    @State private var tagFeedback: NoteTagFeedback?
    @State private var tagFeedbackDismissTask: Task<Void, Never>?
    @State private var pdfShareState = PDFShareState.unavailable
    @State private var pdfShareRetryID = 0
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
        .scrollEdgeEffectStyle(.soft, for: .top)
        .inspector(isPresented: $isAttachmentInspectorPresented) {
            AttachmentInspectorView(
                store: store,
                isEditing: isEditing,
                insertAttachment: insertAttachment,
                removeTag: removeTag
            )
        }
        .overlay(alignment: tagFeedbackAlignment) {
            if let tagFeedback {
                TagFeedbackView(feedback: tagFeedback)
                    .padding(tagFeedbackPaddingEdges, 24)
                    .transition(tagFeedbackTransition)
            }
        }
        #if os(iOS)
        .overlay(alignment: floatingButtonAlignment) {
            if store.hasSelection {
                FloatingEditModeButton(isEditing: isEditing) {
                    isEditing.toggle()
                }
                .padding(.trailing, 24)
                .padding(floatingButtonVerticalPaddingEdge, 24)
            }
        }
        .modifier(imagePickerPresentationModifier)
        #endif
        .onChange(of: attachmentSelectionRequest) {
            importAttachmentFromSelectionRequest()
        }
        .onChange(of: store.selectedNoteID) {
            isEditing = false
            undoRedoAvailability = .disabled
            clearTagFeedback()
            if !store.hasSelection {
                isAttachmentInspectorPresented = false
            }
        }
        .onChange(of: editorFocusRequest) {
            if editorFocusRequest > 0 {
                isEditing = true
            }
        }
        .task(id: pdfShareTask) {
            let snapshot = pdfShareSnapshot
            pdfShareState = snapshot == nil ? .unavailable : .generating
            guard let snapshot else {
                return
            }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }

            do {
                let item = try NotePDFExporter().export(snapshot: snapshot)
                guard !Task.isCancelled else {
                    return
                }
                pdfShareState = .ready(item)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                AppLog.error("Failed to prepare PDF for sharing: \(error.localizedDescription)")
                pdfShareState = .failed
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
            headingFormattingRequest: headingFormattingRequest,
            boldFormattingRequest: boldFormattingRequest,
            italicFormattingRequest: italicFormattingRequest,
            codeFormattingRequest: codeFormattingRequest,
            linkFormattingRequest: linkFormattingRequest,
            tableFormattingRequest: tableFormattingRequest,
            imageFormattingRequest: imageFormattingRequest,
            attachmentFormattingRequest: attachmentFormattingRequest,
            linePrefixFormattingRequest: linePrefixFormattingRequest,
            undoRequest: undoRequest,
            redoRequest: redoRequest,
            focusFirstLineRequest: editorFocusRequest,
            commitTag: commitTag,
            onTagCommitResult: showTagFeedback,
            onUndoRedoAvailabilityChanged: updateUndoRedoAvailability
        )
    }

    private var preview: some View {
        MarkdownPreview(
            markdown: store.editorText,
            context: .textBundle(noteURL: store.selectedNoteURL),
            tags: store.selectedNoteTags
        )
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
            Button {
                isEditing.toggle()
            } label: {
                Image(systemName: isEditing ? "checkmark" : "pencil")
            }
            .help(isEditing ? "Done" : "Edit")
            .accessibilityLabel(isEditing ? "Done" : "Edit")
            .disabled(!store.hasSelection)
        }
        #endif
        #if os(iOS)
        if isEditing {
            EditorUndoRedoToolbar(
                availability: undoRedoAvailability,
                undo: undo,
                redo: redo
            )
        }
        #else
        if isEditing {
            EditorUndoRedoToolbar(
                availability: undoRedoAvailability,
                undo: undo,
                redo: redo
            )
        }
        MarkdownFormattingToolbar(
            applyHeading: handleHeading,
            applyFormatting: handleFormattingCommand,
            isEnabled: store.hasSelection && isEditing
        )
        #endif
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            Button("Attach File", systemImage: "paperclip") {
                presentAttachmentPicker()
            }
            .labelStyle(.iconOnly)
            .help("Attach File")
            .accessibilityLabel("Attach File")
            .disabled(!store.hasSelection || !isEditing)
        }
        ToolbarItem(placement: .primaryAction) {
            switch pdfShareState {
            case let .ready(item):
                ShareLink(
                    item: item,
                    preview: SharePreview(item.suggestedFilename)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
                .help("Share")
                .accessibilityLabel("Share")
            case .failed:
                Button("Retry Share", systemImage: "arrow.clockwise") {
                    pdfShareRetryID += 1
                }
                .labelStyle(.iconOnly)
                .help("Retry Share")
                .accessibilityLabel("Retry Share")
            case .generating:
                Button("Preparing Share", systemImage: "square.and.arrow.up") {}
                    .labelStyle(.iconOnly)
                    .help("Preparing PDF to share")
                    .accessibilityLabel("Preparing PDF to share")
                    .disabled(true)
            case .unavailable:
                Button("Share", systemImage: "square.and.arrow.up") {}
                    .labelStyle(.iconOnly)
                    .help("Share")
                    .accessibilityLabel("Share")
                    .disabled(true)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isAttachmentInspectorPresented.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("Attachments")
            .help("Attachments")
            .disabled(!store.hasSelection)
        }
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
    private var pdfShareSnapshot: NotePDFSnapshot? {
        guard store.hasSelection,
              let noteURL = store.selectedNoteURL,
              let noteSummary = store.selectedNoteSummary
        else {
            return nil
        }

        return NotePDFSnapshot(
            markdown: store.editorText,
            noteURL: noteURL,
            previewFontName: previewFontName,
            previewUsesEditorTheme: previewUsesEditorTheme,
            isDarkMode: colorScheme == .dark,
            suggestedFilename: noteSummary.url.lastPathComponent
        )
    }

    private var pdfShareTask: PDFShareTask {
        PDFShareTask(snapshot: pdfShareSnapshot, retryID: pdfShareRetryID)
    }

    private func undo() {
        undoRequest += 1
    }

    private func redo() {
        redoRequest += 1
    }

    private func updateUndoRedoAvailability(_ availability: EditorUndoRedoAvailability) {
        undoRedoAvailability = availability
    }

    private func commitTag(_ tag: NoteTag) -> NoteTagMutationResult? {
        store.addTag(tag)
    }

    private func removeTag(_ tag: NoteTag) {
        Task {
            await store.removeTag(tag)
        }
    }

    private func showTagFeedback(_ result: NoteTagMutationResult) {
        tagFeedbackDismissTask?.cancel()

        let feedback = switch result {
        case let .added(tag):
            NoteTagFeedback(message: "\(tag.prefixedDisplayName) added")
        case .duplicate:
            NoteTagFeedback(message: "Tag already added")
        }

        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.2)) {
            tagFeedback = feedback
        }

        tagFeedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeIn(duration: reduceMotion ? 0.12 : 0.2)) {
                tagFeedback = nil
            }
        }
    }

    private func clearTagFeedback() {
        tagFeedbackDismissTask?.cancel()
        tagFeedbackDismissTask = nil
        tagFeedback = nil
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
        case .code:
            codeFormattingRequest += 1
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

    private var floatingButtonAlignment: Alignment {
        #if os(macOS)
        .topTrailing
        #else
        .bottomTrailing
        #endif
    }

    private var floatingButtonVerticalPaddingEdge: Edge.Set {
        #if os(macOS)
        .top
        #else
        .bottom
        #endif
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

    private var tagFeedbackAlignment: Alignment {
        #if os(iOS)
        .trailing
        #else
        .bottom
        #endif
    }

    private var tagFeedbackPaddingEdges: Edge.Set {
        #if os(iOS)
        .trailing
        #else
        .bottom
        #endif
    }

    private var tagFeedbackTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        #if os(iOS)
        return .move(edge: .trailing).combined(with: .opacity)
        #else
        return .move(edge: .bottom).combined(with: .opacity)
        #endif
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

/// Describes the short-lived result message shown after a tag mutation.
private struct NoteTagFeedback: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// Tracks whether PDF sharing is unavailable, preparing, or ready for presentation.
private enum PDFShareState {
    case unavailable
    case generating
    case ready(NotePDFShareItem)
    case failed
}

/// Carries the generated PDF and its presentation identity across SwiftUI updates.
private struct PDFShareTask: Equatable {
    let snapshot: NotePDFSnapshot?
    let retryID: Int
}

/// Presents tag mutation feedback without coupling the editor to alert presentation.
private struct TagFeedbackView: View {
    let feedback: NoteTagFeedback

    var body: some View {
        Label(feedback.message, systemImage: "tag")
            .font(.callout)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.secondary.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(radius: 8, y: 2)
            .accessibilityLabel(feedback.message)
    }
}
