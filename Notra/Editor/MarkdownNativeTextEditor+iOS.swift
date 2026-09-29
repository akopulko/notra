import Foundation
import SwiftUI

#if os(iOS)
import UIKit

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
            button.accessibilityLabel = String(localized: NoteFormattingCommand.heading.title)
            button.tintColor = .label
            button.menu = UIMenu(
                children: MarkdownHeadingLevel.allCases.map { level in
                    UIAction(title: String(localized: level.menuTitle)) { [weak self] _ in
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
            button.accessibilityLabel = String(localized: command.title)
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
            button.accessibilityLabel = String(localized: "Attachments")
            button.accessibilityHint = String(localized: "Choose a photo or attach a file")
            button.tintColor = .label
            button.menu = UIMenu(
                children: AttachmentKeyboardMenuItem.allCases.map { item in
                    UIAction(title: String(localized: item.title), image: UIImage(systemName: item.systemImage)) { [weak self] _ in
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
            textView.isOpaque = false
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
                title: String(localized: NoteFormattingCommand.heading.title),
                image: UIImage(systemName: NoteFormattingCommand.heading.systemImage),
                children: MarkdownHeadingLevel.allCases.map { level in
                    UIAction(title: String(localized: level.menuTitle)) { [weak self] _ in
                        self?.parent.bridge.applyHeading?(level)
                    }
                }
            )

            var items: [UIMenuElement] = [headingMenu]
            for command in formattingCommands {
                items.append(
                    UIAction(
                        title: String(localized: command.title),
                        image: UIImage(systemName: command.systemImage)
                    ) { [weak self] _ in
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
#endif
