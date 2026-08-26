import SwiftUI

#if os(iOS)
import UIKit

struct NativeFontPicker: UIViewControllerRepresentable {
    @Binding var fontName: String
    let fontSize: Double?
    let fixedPitchOnly: Bool

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.includeFaces = true

        if fixedPitchOnly {
            configuration.filteredTraits = .traitMonoSpace
        }

        let picker = UIFontPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        picker.selectedFontDescriptor = selectedFontDescriptor
        return picker
    }

    func updateUIViewController(_ uiViewController: UIFontPickerViewController, context _: Context) {
        uiViewController.selectedFontDescriptor = selectedFontDescriptor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(fontName: $fontName)
    }

    private var selectedFontDescriptor: UIFontDescriptor? {
        guard !fontName.isEmpty else {
            return nil
        }

        return UIFontDescriptor(name: fontName, size: CGFloat(fontSize ?? AppearanceFont.defaultSize))
    }

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        @Binding private var fontName: String

        init(fontName: Binding<String>) {
            _fontName = fontName
        }

        func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
            guard let postScriptName = viewController.selectedFontDescriptor?.postscriptName else {
                return
            }

            fontName = postScriptName
        }
    }
}
#elseif os(macOS)
import AppKit

@MainActor
final class NativeFontPanelController: NSObject, NSFontChanging {
    static let shared = NativeFontPanelController()

    private var selection: Binding<String>?
    private var size: Binding<Double>?
    private var fixedPitchOnly = false

    func show(selection: Binding<String>, size: Binding<Double>?, fixedPitchOnly: Bool) {
        self.selection = selection
        self.size = size
        self.fixedPitchOnly = fixedPitchOnly

        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))
        fontManager.setSelectedFont(
            selectedFont(named: selection.wrappedValue, size: size?.wrappedValue),
            isMultiple: false
        )

        let panel = NSFontPanel.shared
        panel.setPanelFont(
            selectedFont(named: selection.wrappedValue, size: size?.wrappedValue),
            isMultiple: false
        )
        panel.orderFrontRegardless()
    }

    @objc
    func changeFont(_ sender: NSFontManager?) {
        guard let sender, let selection else {
            return
        }

        let font = sender.convert(selectedFont(named: selection.wrappedValue, size: size?.wrappedValue))

        if fixedPitchOnly, !font.isFixedPitch {
            return
        }

        selection.wrappedValue = font.fontName
        size?.wrappedValue = font.pointSize
    }

    func validModesForFontPanel(_: NSFontPanel) -> NSFontPanel.ModeMask {
        if size == nil {
            return [.face, .collection]
        }

        return [.face, .size, .collection]
    }

    private func selectedFont(named fontName: String, size: Double?) -> NSFont {
        let pointSize = CGFloat(size ?? AppearanceFont.defaultSize)

        if !fontName.isEmpty, let font = NSFont(name: fontName, size: pointSize) {
            return font
        }

        if fixedPitchOnly, let font = NSFont.userFixedPitchFont(ofSize: pointSize) {
            return font
        }

        return NSFont.systemFont(ofSize: pointSize)
    }
}
#endif
