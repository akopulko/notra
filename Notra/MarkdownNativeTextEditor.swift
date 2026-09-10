import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(iOS)
/// Wraps UITextView and keeps SwiftUI text, selection, highlighting, and undo state synchronized.
struct MarkdownNativeTextEditor: UIViewRepresentable {
    @Binding var text: String
    let fontName: String
    let fontSize: Double
    let theme: MarkdownTheme
    let bridge: MarkdownTextEditorBridge
    let selectionStore: MarkdownEditorSelectionStore
    /// Monotonic request that makes this native text view the keyboard target.
    let focusEditorRequest: Int

    /// Creates the delegate object that owns native text-view configuration and callbacks.
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Returns the configured text view reused across SwiftUI body updates.
    func makeUIView(context: Context) -> UITextView {
        context.coordinator.parent = self
        return context.coordinator.textView
    }

    /// Pushes SwiftUI state changes into UIKit without replacing the user's native selection.
    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(textView: textView)
    }
}

extension MarkdownNativeTextEditor {
    /// Hosts the horizontally scrolling iOS formatting controls above the keyboard.
    final class AccessoryContainerView: UIView {
        static let barHeight: CGFloat = 44
        private static let horizontalMargin: CGFloat = 8
        private static let verticalMargin: CGFloat = 6
        private static let cornerRadius: CGFloat = 18

        private let applyHeading: (MarkdownHeadingLevel) -> Void
        private let applyFormatting: (NoteFormattingCommand) -> Void
        private let choosePhoto: () -> Void
        private let attachFile: () -> Void

        init(
            applyHeading: @escaping (MarkdownHeadingLevel) -> Void,
            applyFormatting: @escaping (NoteFormattingCommand) -> Void,
            choosePhoto: @escaping () -> Void,
            attachFile: @escaping () -> Void
        ) {
            self.applyHeading = applyHeading
            self.applyFormatting = applyFormatting
            self.choosePhoto = choosePhoto
            self.attachFile = attachFile
            super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.intrinsicHeight))
            setUp()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: Self.intrinsicHeight)
        }

        private static var intrinsicHeight: CGFloat {
            barHeight + verticalMargin * 2
        }

        private func setUp() {
            backgroundColor = .clear

            let glassView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glassView.layer.cornerRadius = Self.cornerRadius
            glassView.layer.cornerCurve = .continuous
            glassView.clipsToBounds = true
            glassView.layer.borderWidth = 0.5
            glassView.layer.borderColor = UIColor.separator.cgColor
            glassView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glassView)

            let scrollView = UIScrollView()
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            glassView.contentView.addSubview(scrollView)

            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = 20
            stackView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(stackView)

            stackView.addArrangedSubview(makeHeadingButton())
            for command in formattingCommands {
                stackView.addArrangedSubview(makeFormattingButton(for: command))
            }
            stackView.addArrangedSubview(makeAttachmentMenuButton())

            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalMargin),
                glassView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalMargin),
                glassView.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalMargin),
                glassView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalMargin),
                scrollView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
                stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
                stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
                stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
            ])
        }

        /// Uses the same command ordering as the editor menu and SwiftUI toolbar.
        private var formattingCommands: [NoteFormattingCommand] {
            NoteFormattingCommand.keyboardAccessoryCommands
        }

        private func makeHeadingButton() -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: NoteFormattingCommand.heading.systemImage), for: .normal)
            button.accessibilityLabel = NoteFormattingCommand.heading.title
            button.tintColor = .label
            button.menu = UIMenu(
                children: MarkdownHeadingLevel.allCases.map { level in
                    UIAction(title: level.menuTitle) { [weak self] _ in
                        self?.applyHeading(level)
                    }
                }
            )
            button.showsMenuAsPrimaryAction = true
            return button
        }

        private func makeFormattingButton(for command: NoteFormattingCommand) -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: command.systemImage), for: .normal)
            button.accessibilityLabel = command.title
            button.tintColor = .label
            button.addAction(
                UIAction { [weak self] _ in
                    self?.applyFormatting(command)
                },
                for: .touchUpInside
            )
            return button
        }

        private func makeAttachmentMenuButton() -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "paperclip"), for: .normal)
            button.accessibilityLabel = "Attachments"
            button.accessibilityHint = "Choose a photo or attach a file"
            button.tintColor = .label
            button.menu = UIMenu(
                children: AttachmentKeyboardMenuItem.allCases.map { item in
                    UIAction(title: item.title, image: UIImage(systemName: item.systemImage)) { [weak self] _ in
                        self?.performAttachmentMenuItem(item)
                    }
                }
            )
            button.showsMenuAsPrimaryAction = true
            return button
        }

        private func performAttachmentMenuItem(_ item: AttachmentKeyboardMenuItem) {
            switch item {
            case .choosePhoto:
                choosePhoto()
            case .attachFile:
                attachFile()
            }
        }
    }

    /// Bridges UITextView delegate events to the shared SwiftUI editor bridge.
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownNativeTextEditor
        let textView = FocusableTextView()
        private var accessoryContainer: AccessoryContainerView?
        private var cache = MarkdownHighlightCache()
        private var lastText = ""
        private var lastFont: UIFont?
        private var lastTheme: MarkdownTheme?
        private var pendingProgrammaticSelection: MarkdownEditorSelectionSnapshot?
        private var pendingTextEdit: MarkdownTextEdit?
        private var highlightTask: Task<Void, Never>?
        private var highlightGeneration = 0
        private var remainingFocusAttempts = 0
        private var lastFocusEditorRequest = 0

        init(parent: MarkdownNativeTextEditor) {
            self.parent = parent
            super.init()
            configureTextView()
            wireBridge()
            textView.didMoveToWindowHandler = { [weak self] in
                self?.focusIfPossible()
            }
            receiveFocusRequestIfNeeded()
        }

        deinit {
            highlightTask?.cancel()
        }

        /// Applies pending text, font, theme, selection, and undo-state changes to UIKit.
        func update(textView: UITextView) {
            let font = currentFont

            if (textView.text ?? "") != parent.text {
                replaceText(parent.text)
            }

            if let pendingSelection = pendingProgrammaticSelection {
                pendingProgrammaticSelection = nil
                setSelection(pendingSelection)
            }

            if lastFont != font {
                lastFont = font
                textView.font = font
                textView.typingAttributes = typingAttributes
            }

            if lastTheme != parent.theme {
                refreshHighlight()
            }

            receiveFocusRequestIfNeeded()
            focusIfPossible()
        }

        /// Sends user edits through incremental highlighting before publishing the binding change.
        func textViewDidChange(_: UITextView) {
            handleTextChanged()
        }

        /// Records native selection movement for selection-aware formatting commands.
        func textViewDidChangeSelection(_ textView: UITextView) {
            recordSelection(textView.selectedRange)
        }

        func textView(
            _: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            pendingTextEdit = MarkdownTextEdit(range: range, replacementUTF16Length: text.utf16.count)
            return true
        }

        func textView(
            _: UITextView,
            editMenuForTextInRanges _: [NSValue],
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            var children = suggestedActions
            children.append(contentsOf: buildFormattingMenu())
            return UIMenu(children: children)
        }

        private func configureTextView() {
            textView.delegate = self
            textView.isScrollEnabled = true
            textView.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
            textView.textContainer.lineFragmentPadding = 0
            textView.layoutManager.allowsNonContiguousLayout = true
            // Keep the editor canvas owned by SwiftUI/system chrome; themes only change text colours.
            textView.backgroundColor = .clear
            textView.autocapitalizationType = .sentences
            textView.autocorrectionType = .default
            textView.spellCheckingType = .no
            textView.font = currentFont
            configureAccessoryView()
        }

        private func configureAccessoryView() {
            let container = AccessoryContainerView(
                applyHeading: { [weak self] level in
                    self?.parent.bridge.applyHeading?(level)
                },
                applyFormatting: { [weak self] command in
                    self?.parent.bridge.applyFormattingCommand?(command)
                },
                choosePhoto: { [weak self] in
                    self?.parent.bridge.applyFormattingCommand?(.image)
                },
                attachFile: { [weak self] in
                    self?.parent.bridge.requestAttachmentSelection?()
                }
            )
            accessoryContainer = container
            textView.inputAccessoryView = container
        }

        private func wireBridge() {
            parent.bridge.applyProgrammaticEdit = { [weak self] text, selection in
                self?.applyProgrammaticEdit(text: text, selection: selection)
            }
            parent.bridge.focusEditor = { [weak self] in
                self?.requestEditorFocus()
            }
            parent.bridge.refreshHighlight = { [weak self] in
                self?.refreshHighlight()
            }
            parent.bridge.performUndo = { [weak self] in
                self?.performUndo()
            }
            parent.bridge.performRedo = { [weak self] in
                self?.performRedo()
            }
            parent.bridge.refreshUndoRedoAvailability = { [weak self] in
                self?.updateUndoRedoAvailability()
            }
        }

        private func requestEditorFocus() {
            textView.isFocusRequested = true
            // A NavigationSplitView can restore the sidebar as first responder in the same update
            // that inserts the editor. Reassert focus over subsequent UIKit passes so the editor
            // becomes the final keyboard target after the split view has settled.
            remainingFocusAttempts = 3
            scheduleFocusAttempt()
        }

        private func receiveFocusRequestIfNeeded() {
            guard parent.focusEditorRequest > lastFocusEditorRequest else {
                return
            }

            lastFocusEditorRequest = parent.focusEditorRequest
            requestEditorFocus()
        }

        private func focusIfPossible() {
            guard textView.isFocusRequested, textView.window != nil else {
                return
            }

            _ = textView.becomeFirstResponder()
            scheduleFocusAttempt()
        }

        private func scheduleFocusAttempt() {
            guard textView.isFocusRequested, remainingFocusAttempts > 0 else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, textView.isFocusRequested else {
                    return
                }

                guard textView.window != nil else {
                    return
                }

                remainingFocusAttempts -= 1
                _ = textView.becomeFirstResponder()
                if remainingFocusAttempts > 0 {
                    scheduleFocusAttempt()
                } else {
                    textView.isFocusRequested = false
                }
            }
        }

        private func buildFormattingMenu() -> [UIMenuElement] {
            let headingMenu = UIMenu(
                title: NoteFormattingCommand.heading.title,
                image: UIImage(systemName: NoteFormattingCommand.heading.systemImage),
                children: MarkdownHeadingLevel.allCases.map { level in
                    UIAction(title: level.menuTitle) { [weak self] _ in
                        self?.parent.bridge.applyHeading?(level)
                    }
                }
            )

            var items: [UIMenuElement] = [headingMenu]
            for command in formattingCommands {
                items.append(
                    UIAction(title: command.title, image: UIImage(systemName: command.systemImage)) { [weak self] _ in
                        self?.parent.bridge.applyFormattingCommand?(command)
                    }
                )
            }
            return items
        }

        private var formattingCommands: [NoteFormattingCommand] {
            NoteFormattingCommand.editorMenuCommands
        }

        /// Applies only changed highlight lines and publishes the new editor text.
        private func handleTextChanged() {
            let newText = textView.text ?? ""
            guard newText != lastText else {
                return
            }

            lastText = newText
            let edit = pendingTextEdit
            pendingTextEdit = nil
            scheduleHighlight(for: newText, edit: edit)
            parent.text = newText
            updateUndoRedoAvailability()
        }

        /// Replaces native text during external selection changes without echoing a stale callback.
        private func replaceText(_ newText: String) {
            guard newText != lastText else {
                return
            }

            cancelDeferredHighlight()
            lastText = newText
            cache.setText(newText)
            textView.text = newText
            let font = currentFont
            cache.applyColors(
                theme: parent.theme,
                font: font,
                baseColor: parent.theme.editor.normalText.platformColor,
                to: textView.textStorage,
                lines: 0..<cache.count
            )
            lastFont = font
            lastTheme = parent.theme
        }

        private func applyProgrammaticEdit(text newText: String, selection: MarkdownEditorSelectionSnapshot) {
            pendingProgrammaticSelection = selection
            if (textView.text ?? "") != newText {
                applyUndoableTextReplacement(text: newText, selection: selection)
            } else {
                setSelection(selection)
            }
        }

        private func applyUndoableTextReplacement(
            text newText: String,
            selection newSelection: MarkdownEditorSelectionSnapshot
        ) {
            let oldText = textView.text ?? ""
            let oldSelection = selectionSnapshot(from: textView.selectedRange) ?? MarkdownEditorSelectionSnapshot()

            replaceText(newText)
            setSelection(newSelection)
            parent.text = newText

            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.applyUndoableTextReplacement(text: oldText, selection: oldSelection)
            }
            updateUndoRedoAvailability()
        }

        private func performUndo() {
            guard let undoManager = textView.undoManager, undoManager.canUndo else {
                updateUndoRedoAvailability()
                return
            }

            undoManager.undo()
            handleTextChanged()
            updateUndoRedoAvailability()
        }

        private func performRedo() {
            guard let undoManager = textView.undoManager, undoManager.canRedo else {
                updateUndoRedoAvailability()
                return
            }

            undoManager.redo()
            handleTextChanged()
            updateUndoRedoAvailability()
        }

        private func updateUndoRedoAvailability() {
            let undoManager = textView.undoManager
            parent.bridge.reportUndoRedoAvailability?(
                EditorUndoRedoAvailability(
                    canUndo: undoManager?.canUndo ?? false,
                    canRedo: undoManager?.canRedo ?? false
                )
            )
        }

        private func refreshHighlight() {
            cancelDeferredHighlight()
            guard !cache.isEmpty else {
                return
            }

            let font = currentFont
            cache.applyColors(
                theme: parent.theme,
                font: font,
                baseColor: parent.theme.editor.normalText.platformColor,
                to: textView.textStorage,
                lines: 0..<cache.count
            )
            lastFont = font
            lastTheme = parent.theme
        }

        /// Coalesces native typing so syntax parsing cannot consume every input event.
        private func scheduleHighlight(for text: String, edit: MarkdownTextEdit?) {
            highlightTask?.cancel()
            highlightGeneration &+= 1
            let generation = highlightGeneration
            highlightTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(75))
                guard !Task.isCancelled,
                      let self,
                      generation == highlightGeneration,
                      let changedRange = cache.updateText(text, edit: edit)
                else {
                    return
                }

                cache.applyColors(
                    theme: parent.theme,
                    font: currentFont,
                    baseColor: parent.theme.editor.normalText.platformColor,
                    to: textView.textStorage,
                    lines: changedRange
                )
            }
        }

        private func cancelDeferredHighlight() {
            highlightTask?.cancel()
            highlightTask = nil
            highlightGeneration &+= 1
        }

        private func setSelection(_ selection: MarkdownEditorSelectionSnapshot) {
            let range = nativeRange(from: selection)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
            recordSelection(range)
        }

        private func recordSelection(_ range: NSRange) {
            guard let snapshot = selectionSnapshot(from: range) else {
                return
            }

            parent.selectionStore.record(snapshot)
        }

        private func selectionSnapshot(from range: NSRange) -> MarkdownEditorSelectionSnapshot? {
            guard range.location != NSNotFound,
                  range.location >= 0,
                  range.length >= 0,
                  range.location + range.length <= (textView.text ?? "").utf16.count
            else {
                return nil
            }

            return MarkdownEditorSelectionSnapshot(
                lowerOffset: range.location,
                upperOffset: range.location + range.length
            )
        }

        private func nativeRange(from snapshot: MarkdownEditorSelectionSnapshot) -> NSRange {
            let lowerOffset = min(max(snapshot.lowerOffset, 0), (textView.text ?? "").utf16.count)
            let upperOffset = min(max(snapshot.upperOffset, lowerOffset), (textView.text ?? "").utf16.count)
            return NSRange(location: lowerOffset, length: upperOffset - lowerOffset)
        }

        private var currentFont: UIFont {
            AppearanceFont.nativeEditorFont(named: parent.fontName, size: parent.fontSize)
        }

        private var typingAttributes: [NSAttributedString.Key: Any] {
            [.font: currentFont, .foregroundColor: parent.theme.editor.normalText.platformColor]
        }
    }

    /// Records a focus request until UIKit attaches the editor to a window.
    final class FocusableTextView: UITextView {
        var isFocusRequested = false
        var didMoveToWindowHandler: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            didMoveToWindowHandler?()
        }
    }
}
#elseif os(macOS)
/// Wraps NSTextView with the same editor contract used by the iOS implementation.
struct MarkdownNativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontName: String
    let fontSize: Double
    let theme: MarkdownTheme
    let bridge: MarkdownTextEditorBridge
    let selectionStore: MarkdownEditorSelectionStore
    /// Requests keyboard focus when the command inserts the AppKit editor.
    let focusEditorRequest: Int

    /// Creates the delegate object that owns native text-view configuration and callbacks.
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Returns the scroll view containing the configured AppKit text view.
    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.parent = self
        return context.coordinator.scrollView
    }

    /// Pushes SwiftUI state changes into AppKit without discarding native selection state.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(scrollView: scrollView)
    }
}

extension MarkdownNativeTextEditor {
    /// Bridges NSTextView delegate events to the shared SwiftUI editor bridge.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNativeTextEditor
        let scrollView = NSScrollView()
        let textView = FocusableTextView()
        private var cache = MarkdownHighlightCache()
        private var lastText = ""
        private var lastFont: NSFont?
        private var lastFocusEditorRequest = 0
        private var lastTheme: MarkdownTheme?
        private var pendingProgrammaticSelection: MarkdownEditorSelectionSnapshot?
        private var pendingTextEdit: MarkdownTextEdit?
        private var highlightTask: Task<Void, Never>?
        private var highlightGeneration = 0

        init(parent: MarkdownNativeTextEditor) {
            self.parent = parent
            super.init()
            configureTextView()
            configureScrollView()
            wireBridge()
        }

        deinit {
            highlightTask?.cancel()
        }

        /// Applies pending text, font, theme, selection, and undo-state changes to AppKit.
        func update(scrollView _: NSScrollView) {
            let font = currentFont

            if textView.string != parent.text {
                replaceText(parent.text)
            }

            if let pendingSelection = pendingProgrammaticSelection {
                pendingProgrammaticSelection = nil
                setSelection(pendingSelection)
            }

            if lastFont != font {
                lastFont = font
                textView.font = font
                textView.typingAttributes = [.font: font, .foregroundColor: parent.theme.editor.normalText.platformColor]
            }

            if lastTheme != parent.theme {
                refreshHighlight()
            }

            if parent.focusEditorRequest > lastFocusEditorRequest {
                lastFocusEditorRequest = parent.focusEditorRequest
                textView.requestKeyboardFocus()
            }
        }

        /// Sends user edits through incremental highlighting before publishing the binding change.
        func textDidChange(_: Notification) {
            handleTextChanged()
        }

        /// Records native selection movement for selection-aware formatting commands.
        func textViewDidChangeSelection(_: Notification) {
            recordSelection(textView.selectedRange())
        }

        func textView(
            _: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            let replacement = replacementString ?? ""
            pendingTextEdit = MarkdownTextEdit(
                range: affectedCharRange,
                replacementUTF16Length: replacement.utf16.count
            )
            return true
        }

        func textView(
            _: NSTextView,
            menu _: NSMenu,
            for _: NSEvent,
            at characterIndex: Int
        ) -> NSMenu? {
            buildContextMenu(at: characterIndex)
        }

        private func configureTextView() {
            textView.delegate = self
            textView.isRichText = false
            textView.allowsUndo = true
            textView.isContinuousSpellCheckingEnabled = false
            textView.font = currentFont
            textView.textContainerInset = NSSize(width: 8, height: 6)
            textView.textContainer?.lineFragmentPadding = 0
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.minSize = .zero
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            textView.importsGraphics = false
            textView.usesFindBar = false
            textView.usesAdaptiveColorMappingForDarkAppearance = false
            // Keep the text view canvas transparent so AppKit does not draw a darker editor plate.
            textView.drawsBackground = false
        }

        private func configureScrollView() {
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            // Keep the macOS editor background transparent so syntax themes cannot tint the canvas.
            scrollView.drawsBackground = false
        }

        private func wireBridge() {
            parent.bridge.applyProgrammaticEdit = { [weak self] text, selection in
                self?.applyProgrammaticEdit(text: text, selection: selection)
            }
            parent.bridge.focusEditor = { [weak self] in
                self?.textView.requestKeyboardFocus()
            }
            parent.bridge.refreshHighlight = { [weak self] in
                self?.refreshHighlight()
            }
            parent.bridge.performUndo = { [weak self] in
                self?.performUndo()
            }
            parent.bridge.performRedo = { [weak self] in
                self?.performRedo()
            }
            parent.bridge.refreshUndoRedoAvailability = { [weak self] in
                self?.updateUndoRedoAvailability()
            }
        }

        private func appendHeadingMenu(to menu: NSMenu) {
            let headingItem = NSMenuItem(
                title: NoteFormattingCommand.heading.title,
                action: nil,
                keyEquivalent: ""
            )
            headingItem.image = NSImage(
                systemSymbolName: NoteFormattingCommand.heading.systemImage,
                accessibilityDescription: NoteFormattingCommand.heading.title
            )
            let submenu = NSMenu()
            for level in MarkdownHeadingLevel.allCases {
                let item = NSMenuItem(
                    title: level.menuTitle,
                    action: #selector(applyHeadingFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = level
                submenu.addItem(item)
            }
            headingItem.submenu = submenu
            menu.addItem(headingItem)
        }

        @objc
        private func applyFormattingFromMenu(_ sender: NSMenuItem) {
            guard let command = sender.representedObject as? NoteFormattingCommand else {
                return
            }
            parent.bridge.applyFormattingCommand?(command)
        }

        @objc
        private func applyHeadingFromMenu(_ sender: NSMenuItem) {
            guard let level = sender.representedObject as? MarkdownHeadingLevel else {
                return
            }
            parent.bridge.applyHeading?(level)
        }

        private var formattingCommands: [NoteFormattingCommand] {
            NoteFormattingCommand.editorMenuCommands
        }

        /// Applies only changed highlight lines and publishes the new editor text.
        private func handleTextChanged() {
            let newText = textView.string
            guard newText != lastText else {
                return
            }

            lastText = newText
            let edit = pendingTextEdit
            pendingTextEdit = nil
            scheduleHighlight(for: newText, edit: edit)
            parent.text = newText
            updateUndoRedoAvailability()
        }

        /// Replaces native text during external selection changes without echoing a stale callback.
        private func replaceText(_ newText: String) {
            guard newText != lastText else {
                return
            }

            cancelDeferredHighlight()
            lastText = newText
            cache.setText(newText)
            textView.string = newText

            let font = currentFont
            applyHighlight(lines: 0..<cache.count)
            lastFont = font
            lastTheme = parent.theme
        }

        private func applyProgrammaticEdit(text newText: String, selection: MarkdownEditorSelectionSnapshot) {
            pendingProgrammaticSelection = selection
            if textView.string != newText {
                applyUndoableTextReplacement(text: newText, selection: selection)
            } else {
                setSelection(selection)
            }
        }

        private func applyUndoableTextReplacement(
            text newText: String,
            selection newSelection: MarkdownEditorSelectionSnapshot
        ) {
            let oldText = textView.string
            let oldSelection = selectionSnapshot(from: textView.selectedRange()) ?? MarkdownEditorSelectionSnapshot()

            replaceText(newText)
            setSelection(newSelection)
            parent.text = newText

            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.applyUndoableTextReplacement(text: oldText, selection: oldSelection)
            }
            updateUndoRedoAvailability()
        }

        private func performUndo() {
            guard let undoManager = textView.undoManager, undoManager.canUndo else {
                updateUndoRedoAvailability()
                return
            }

            undoManager.undo()
            handleTextChanged()
            updateUndoRedoAvailability()
        }

        private func performRedo() {
            guard let undoManager = textView.undoManager, undoManager.canRedo else {
                updateUndoRedoAvailability()
                return
            }

            undoManager.redo()
            handleTextChanged()
            updateUndoRedoAvailability()
        }

        private func updateUndoRedoAvailability() {
            let undoManager = textView.undoManager
            parent.bridge.reportUndoRedoAvailability?(
                EditorUndoRedoAvailability(
                    canUndo: undoManager?.canUndo ?? false,
                    canRedo: undoManager?.canRedo ?? false
                )
            )
        }

        private func refreshHighlight() {
            cancelDeferredHighlight()
            guard !cache.isEmpty else {
                return
            }

            let font = currentFont
            applyHighlight(lines: 0..<cache.count)
            lastFont = font
            lastTheme = parent.theme
        }

        /// Coalesces native typing so syntax parsing cannot consume every input event.
        private func scheduleHighlight(for text: String, edit: MarkdownTextEdit?) {
            highlightTask?.cancel()
            highlightGeneration &+= 1
            let generation = highlightGeneration
            highlightTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(75))
                guard !Task.isCancelled,
                      let self,
                      generation == highlightGeneration,
                      let changedRange = cache.updateText(text, edit: edit)
                else {
                    return
                }

                applyHighlight(lines: changedRange)
            }
        }

        private func cancelDeferredHighlight() {
            highlightTask?.cancel()
            highlightTask = nil
            highlightGeneration &+= 1
        }

        private func applyHighlight(lines: Range<Int>) {
            guard let layoutManager = textView.layoutManager else {
                return
            }

            cache.applyTemporaryColors(
                theme: parent.theme,
                font: currentFont,
                baseColor: parent.theme.editor.normalText.platformColor,
                to: layoutManager,
                lines: lines
            )
        }

        private func setSelection(_ selection: MarkdownEditorSelectionSnapshot) {
            let range = nativeRange(from: selection)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            recordSelection(range)
        }

        private func restoreSelection(_ selection: MarkdownEditorSelectionSnapshot) {
            let range = nativeRange(from: selection)
            textView.setSelectedRange(range)
            recordSelection(range)
        }

        private func recordSelection(_ range: NSRange) {
            guard let snapshot = selectionSnapshot(from: range) else {
                return
            }

            parent.selectionStore.record(snapshot)
        }

        private func selectionSnapshot(from range: NSRange) -> MarkdownEditorSelectionSnapshot? {
            guard range.location != NSNotFound,
                  range.location >= 0,
                  range.length >= 0,
                  range.location + range.length <= textView.string.utf16.count
            else {
                return nil
            }

            return MarkdownEditorSelectionSnapshot(
                lowerOffset: range.location,
                upperOffset: range.location + range.length
            )
        }

        private func nativeRange(from snapshot: MarkdownEditorSelectionSnapshot) -> NSRange {
            let lowerOffset = min(max(snapshot.lowerOffset, 0), textView.string.utf16.count)
            let upperOffset = min(max(snapshot.upperOffset, lowerOffset), textView.string.utf16.count)
            return NSRange(location: lowerOffset, length: upperOffset - lowerOffset)
        }

        private var currentFont: NSFont {
            AppearanceFont.nativeEditorFont(named: parent.fontName, size: parent.fontSize)
        }
    }
}

extension MarkdownNativeTextEditor {
    /// Delivers focus after AppKit has attached the editor and finished the current view update.
    final class FocusableTextView: NSTextView {
        private var needsKeyboardFocus = false
        private var isFocusScheduled = false

        func requestKeyboardFocus() {
            needsKeyboardFocus = true
            scheduleKeyboardFocus()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleKeyboardFocus()
        }

        private func scheduleKeyboardFocus() {
            guard needsKeyboardFocus, window != nil, !isFocusScheduled else {
                return
            }

            isFocusScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                isFocusScheduled = false
                guard needsKeyboardFocus, let window else {
                    return
                }
                if window.makeFirstResponder(self) {
                    needsKeyboardFocus = false
                }
            }
        }
    }
}

extension MarkdownNativeTextEditor.Coordinator {
    /// Replaces AppKit's text-services menu so editor context actions stay app-owned.
    private func buildContextMenu(at characterIndex: Int) -> NSMenu {
        let menu = NSMenu()
        appendEditMenuItems(to: menu, at: characterIndex)
        menu.addItem(.separator())
        appendHeadingMenu(to: menu)
        for command in formattingCommands {
            appendMenuItem(
                to: menu,
                title: command.title,
                systemImage: command.systemImage,
                action: #selector(applyFormattingFromMenu(_:)),
                target: self,
                representedObject: command
            )
        }
        return menu
    }

    private func appendEditMenuItems(to menu: NSMenu, at characterIndex: Int) {
        appendMenuItem(
            to: menu,
            title: "Select",
            systemImage: "selection.pin.in.out",
            action: #selector(selectWordFromMenu(_:)),
            target: self,
            representedObject: characterIndex,
            isEnabled: canSelectWord(at: characterIndex)
        )
        appendMenuItem(
            to: menu,
            title: "Select All",
            systemImage: "selection.pin.in.out",
            action: #selector(NSText.selectAll(_:)),
            target: textView,
            isEnabled: !textView.string.isEmpty
        )
        appendMenuItem(
            to: menu,
            title: "Cut",
            systemImage: "scissors",
            action: #selector(NSText.cut(_:)),
            target: textView,
            isEnabled: textView.selectedRange().length > 0
        )
        appendMenuItem(
            to: menu,
            title: "Copy",
            systemImage: "doc.on.doc",
            action: #selector(NSText.copy(_:)),
            target: textView,
            isEnabled: textView.selectedRange().length > 0
        )
        appendMenuItem(
            to: menu,
            title: "Paste",
            systemImage: "doc.on.clipboard",
            action: #selector(NSText.paste(_:)),
            target: textView,
            isEnabled: canPasteText
        )
    }

    private func appendMenuItem(
        to menu: NSMenu,
        title: String,
        systemImage: String?,
        action: Selector,
        target: AnyObject?,
        representedObject: Any? = nil,
        isEnabled: Bool = true
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        }
        item.target = target
        item.representedObject = representedObject
        item.isEnabled = isEnabled
        menu.addItem(item)
    }

    private func canSelectWord(at characterIndex: Int) -> Bool {
        characterIndex >= 0 && characterIndex < textView.string.utf16.count
    }

    private var canPasteText: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil)
    }

    @objc
    private func selectWordFromMenu(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int,
              canSelectWord(at: characterIndex)
        else {
            return
        }

        let proposedRange = NSRange(location: characterIndex, length: 0)
        let selectionRange = textView.selectionRange(
            forProposedRange: proposedRange,
            granularity: .selectByWord
        )
        guard selectionRange.location != NSNotFound, selectionRange.length > 0 else {
            return
        }
        textView.setSelectedRange(selectionRange)
    }
}
#endif
