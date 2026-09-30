import Foundation
import SwiftUI

#if os(macOS)
import AppKit

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

        /// Applies pending text, font, theme, and selection changes to AppKit.
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
        }

        private func appendHeadingMenu(to menu: NSMenu) {
            let headingItem = NSMenuItem(
                title: String(localized: NoteFormattingCommand.heading.title),
                action: nil,
                keyEquivalent: ""
            )
            headingItem.image = NSImage(
                systemSymbolName: NoteFormattingCommand.heading.systemImage,
                accessibilityDescription: String(localized: NoteFormattingCommand.heading.title)
            )
            let submenu = NSMenu()
            for level in MarkdownHeadingLevel.allCases {
                let item = NSMenuItem(
                    title: String(localized: level.menuTitle),
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
                title: String(localized: command.title),
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
            title: String(localized: "Select"),
            systemImage: "selection.pin.in.out",
            action: #selector(selectWordFromMenu(_:)),
            target: self,
            representedObject: characterIndex,
            isEnabled: canSelectWord(at: characterIndex)
        )
        appendMenuItem(
            to: menu,
            title: String(localized: "Select All"),
            systemImage: "selection.pin.in.out",
            action: #selector(NSText.selectAll(_:)),
            target: textView,
            isEnabled: !textView.string.isEmpty
        )
        appendMenuItem(
            to: menu,
            title: String(localized: "Cut"),
            systemImage: "scissors",
            action: #selector(NSText.cut(_:)),
            target: textView,
            isEnabled: textView.selectedRange().length > 0
        )
        appendMenuItem(
            to: menu,
            title: String(localized: "Copy"),
            systemImage: "doc.on.doc",
            action: #selector(NSText.copy(_:)),
            target: textView,
            isEnabled: textView.selectedRange().length > 0
        )
        appendMenuItem(
            to: menu,
            title: String(localized: "Paste"),
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
