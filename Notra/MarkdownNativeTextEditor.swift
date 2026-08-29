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
    let theme: MarkdownHighlightTheme
    let bridge: MarkdownTextEditorBridge
    let selectionStore: MarkdownEditorSelectionStore

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

        init(
            applyHeading: @escaping (MarkdownHeadingLevel) -> Void,
            applyFormatting: @escaping (NoteFormattingCommand) -> Void
        ) {
            self.applyHeading = applyHeading
            self.applyFormatting = applyFormatting
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
            NoteFormattingCommand.editorMenuCommands
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
    }

    /// Bridges UITextView delegate events to the shared SwiftUI editor bridge.
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownNativeTextEditor
        let textView = UITextView()
        private var accessoryContainer: AccessoryContainerView?
        private var cache = MarkdownHighlightCache()
        private var lastText = ""
        private var lastFont: UIFont?
        private var lastTheme: MarkdownHighlightTheme?
        private var pendingProgrammaticSelection: MarkdownEditorSelectionSnapshot?

        init(parent: MarkdownNativeTextEditor) {
            self.parent = parent
            super.init()
            configureTextView()
            wireBridge()
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
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n",
                  range.length == 0,
                  textView.markedTextRange == nil,
                  let snapshot = selectionSnapshot(from: range),
                  parent.bridge.commitTagEntry?(snapshot) == true
            else {
                return true
            }

            return false
        }

        func textView(
            _: UITextView,
            editMenuForTextInRanges _: [NSValue],
            suggestedActions _: [UIMenuElement]
        ) -> UIMenu? {
            var children: [UIMenuElement] = buildEditActions()
            children.append(contentsOf: buildFormattingMenu())
            return UIMenu(children: children)
        }

        private func configureTextView() {
            textView.delegate = self
            textView.isScrollEnabled = true
            textView.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
            textView.textContainer.lineFragmentPadding = 0
            textView.layoutManager.allowsNonContiguousLayout = true
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
                self?.textView.becomeFirstResponder()
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

        private func buildEditActions() -> [UIMenuElement] {
            let actions: [(title: String, image: String, selector: Selector)] = [
                ("Select", "selection.pin.in.out", #selector(UIResponderStandardEditActions.select(_:))),
                ("Select All", "selection.pin.in.out", #selector(UIResponderStandardEditActions.selectAll(_:))),
                ("Cut", "scissors", #selector(UIResponderStandardEditActions.cut(_:))),
                ("Copy", "doc.on.doc", #selector(UIResponderStandardEditActions.copy(_:))),
                ("Paste", "doc.on.clipboard", #selector(UIResponderStandardEditActions.paste(_:)))
            ]

            return actions.compactMap { item in
                guard textView.canPerformAction(item.selector, withSender: nil) else {
                    return nil
                }
                return UIAction(title: item.title, image: UIImage(systemName: item.image)) { [weak self] _ in
                    self?.performEditAction(item.selector)
                }
            }
        }

        private func performEditAction(_ selector: Selector) {
            switch selector {
            case #selector(UIResponderStandardEditActions.select(_:)):
                textView.select(nil)
            case #selector(UIResponderStandardEditActions.selectAll(_:)):
                textView.selectAll(nil)
            case #selector(UIResponderStandardEditActions.cut(_:)):
                textView.cut(nil)
            case #selector(UIResponderStandardEditActions.copy(_:)):
                textView.copy(nil)
            case #selector(UIResponderStandardEditActions.paste(_:)):
                textView.paste(nil)
            default:
                break
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
            if let changedRange = cache.updateText(newText) {
                cache.applyColors(
                    theme: parent.theme,
                    font: currentFont,
                    baseColor: .label,
                    to: textView.textStorage,
                    lines: changedRange
                )
            }
            parent.text = newText
            updateUndoRedoAvailability()
        }

        /// Replaces native text during external selection changes without echoing a stale callback.
        private func replaceText(_ newText: String) {
            guard newText != lastText else {
                return
            }

            lastText = newText
            cache.setText(newText)
            textView.text = newText
            let font = currentFont
            cache.applyColors(
                theme: parent.theme,
                font: font,
                baseColor: .label,
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
            guard !cache.isEmpty else {
                return
            }

            let font = currentFont
            cache.applyColors(
                theme: parent.theme,
                font: font,
                baseColor: .label,
                to: textView.textStorage,
                lines: 0..<cache.count
            )
            lastFont = font
            lastTheme = parent.theme
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
            [.font: currentFont, .foregroundColor: UIColor.label]
        }
    }
}
#elseif os(macOS)
/// Wraps NSTextView with the same editor contract used by the iOS implementation.
struct MarkdownNativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontName: String
    let fontSize: Double
    let theme: MarkdownHighlightTheme
    let bridge: MarkdownTextEditorBridge
    let selectionStore: MarkdownEditorSelectionStore

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
        let textView = NSTextView()
        private var cache = MarkdownHighlightCache()
        private var lastText = ""
        private var lastFont: NSFont?
        private var lastTheme: MarkdownHighlightTheme?
        private var pendingProgrammaticSelection: MarkdownEditorSelectionSnapshot?

        init(parent: MarkdownNativeTextEditor) {
            self.parent = parent
            super.init()
            configureTextView()
            configureScrollView()
            wireBridge()
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
                textView.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
            }

            if lastTheme != parent.theme {
                refreshHighlight()
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
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard replacementString == "\n",
                  affectedCharRange.length == 0,
                  !textView.hasMarkedText(),
                  let snapshot = selectionSnapshot(from: affectedCharRange),
                  parent.bridge.commitTagEntry?(snapshot) == true
            else {
                return true
            }

            return false
        }

        func textView(
            _: NSTextView,
            menu: NSMenu,
            for _: NSEvent,
            at _: Int
        ) -> NSMenu? {
            menu.addItem(.separator())
            appendHeadingMenu(to: menu)
            for command in formattingCommands {
                let item = NSMenuItem(
                    title: command.title,
                    action: #selector(applyFormattingFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.image = NSImage(systemSymbolName: command.systemImage, accessibilityDescription: command.title)
                item.target = self
                item.representedObject = command
                menu.addItem(item)
            }
            return menu
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
        }

        private func configureScrollView() {
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false
        }

        private func wireBridge() {
            parent.bridge.applyProgrammaticEdit = { [weak self] text, selection in
                self?.applyProgrammaticEdit(text: text, selection: selection)
            }
            parent.bridge.focusEditor = { [weak self] in
                guard let self else {
                    return
                }
                textView.window?.makeFirstResponder(textView)
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
            if let changedRange = cache.updateText(newText), let storage = textView.textStorage {
                applyHighlight(to: storage, lines: changedRange)
            }
            parent.text = newText
            updateUndoRedoAvailability()
        }

        /// Replaces native text during external selection changes without echoing a stale callback.
        private func replaceText(_ newText: String) {
            guard newText != lastText else {
                return
            }

            lastText = newText
            cache.setText(newText)
            textView.string = newText
            guard let storage = textView.textStorage else {
                return
            }

            let font = currentFont
            applyHighlight(to: storage, lines: 0..<cache.count)
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
            guard !cache.isEmpty, let storage = textView.textStorage else {
                return
            }

            let font = currentFont
            applyHighlight(to: storage, lines: 0..<cache.count)
            lastFont = font
            lastTheme = parent.theme
        }

        private func applyHighlight(to storage: NSMutableAttributedString, lines: Range<Int>) {
            let selection = selectionSnapshot(from: textView.selectedRange())
            cache.applyColors(
                theme: parent.theme,
                font: currentFont,
                baseColor: .labelColor,
                to: storage,
                lines: lines
            )
            if let selection {
                restoreSelection(selection)
            }
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
#endif
