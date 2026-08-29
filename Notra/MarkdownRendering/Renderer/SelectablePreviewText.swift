import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Keeps Markdown preview text visually SwiftUI-rendered while exposing native selection where needed.
struct SelectablePreviewText: View {
    let attributedText: AttributedString
    let selectionText: String
    var selectionFont: MarkdownPreviewSelectionFont = .body

    var body: some View {
        #if os(iOS)
        ZStack(alignment: .topLeading) {
            Text(attributedText)

            UIKitSelectableTextOverlay(
                text: selectionText,
                font: selectionFont.uiFont
            )
            .accessibilityHidden(true)
        }
        #else
        Text(attributedText)
            .textSelection(.enabled)
        #endif
    }
}

#if os(iOS)
/// Mirrors the visible SwiftUI text with an invisible UITextView so iOS shows copy handles and menus.
private struct UIKitSelectableTextOverlay: UIViewRepresentable {
    let text: String
    let font: UIFont

    func makeUIView(context _: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.maximumNumberOfLines = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textColor = .clear
        textView.tintColor = .tintColor
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ textView: UITextView, context _: Context) {
        textView.text = text
        textView.font = font
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context _: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }

        let fittingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let measuredSize = uiView.sizeThatFits(fittingSize)
        return CGSize(width: width, height: measuredSize.height)
    }
}

/// Describes the UIKit font needed by the invisible iOS selection layer.
enum MarkdownPreviewSelectionFont: Equatable {
    case body
    case heading(level: Int, fontName: String, scales: [CGFloat])
    case code
    case callout

    var uiFont: UIFont {
        switch self {
        case .body:
            UIFont.preferredFont(forTextStyle: .body)
        case let .heading(level, fontName, scales):
            headingFont(level: level, fontName: fontName, scales: scales)
        case .code:
            UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        case .callout:
            UIFont.preferredFont(forTextStyle: .callout)
        }
    }

    private func headingFont(level: Int, fontName: String, scales: [CGFloat]) -> UIFont {
        let index = min(max(level, 1), scales.count) - 1
        let size = CGFloat(AppearanceFont.defaultSize) * scales[index]

        if !fontName.isEmpty, let font = UIFont(name: fontName, size: size) {
            return UIFontMetrics(forTextStyle: .title1).scaledFont(for: font)
        }

        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }
}
#else
/// Exists on macOS so shared Markdown renderer call sites can keep one shape.
enum MarkdownPreviewSelectionFont: Equatable {
    case body
    case heading(level: Int, fontName: String, scales: [CGFloat])
    case code
    case callout
}
#endif
