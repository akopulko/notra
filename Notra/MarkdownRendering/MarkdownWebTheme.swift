import Foundation

/// Converts the shared semantic theme into CSS values without defining another colour palette.
struct MarkdownWebTheme {
    let bodyText: String
    let secondaryText: String
    let headingPrimary: String
    let headingSecondary: String
    let headingTertiary: String
    let boldText: String
    let italicText: String
    let strikethroughText: String
    let linkText: String
    let listMarker: String
    let quoteText: String
    let quoteAccent: String
    let border: String
    let inlineCodeText: String
    let inlineCodeBackground: String
    let horizontalRule: String
    let codeBlockText: String
    let codeComment: String
    let codeKeyword: String
    let codeString: String
    let codeNumber: String
    let codeType: String
    let codeFunction: String
    let codeOperator: String
    let codeTag: String
    let codeAttribute: String
    let codeConstant: String

    init(theme: MarkdownTheme?, printable: Bool = false) {
        if printable {
            bodyText = "#111111"
            secondaryText = "#555555"
            headingPrimary = "#111111"
            headingSecondary = "#222222"
            headingTertiary = "#333333"
            boldText = "#111111"
            italicText = "#333333"
            strikethroughText = "#555555"
            linkText = "#1f5fbf"
            listMarker = "#333333"
            quoteText = "#555555"
            quoteAccent = "#888888"
            border = "#b8b8b8"
            inlineCodeText = "#222222"
            inlineCodeBackground = "#f1f1f1"
            horizontalRule = "#b8b8b8"
            codeBlockText = "#222222"
            codeComment = codeBlockText
            codeKeyword = codeBlockText
            codeString = codeBlockText
            codeNumber = codeBlockText
            codeType = codeBlockText
            codeFunction = codeBlockText
            codeOperator = codeBlockText
            codeTag = codeBlockText
            codeAttribute = codeBlockText
            codeConstant = codeBlockText
            return
        }

        guard let theme else {
            bodyText = "CanvasText"
            secondaryText = "GrayText"
            headingPrimary = "CanvasText"
            headingSecondary = "CanvasText"
            headingTertiary = "CanvasText"
            boldText = "CanvasText"
            italicText = "CanvasText"
            strikethroughText = "CanvasText"
            linkText = "LinkText"
            listMarker = "CanvasText"
            quoteText = "GrayText"
            quoteAccent = "GrayText"
            border = "GrayText"
            inlineCodeText = "CanvasText"
            inlineCodeBackground = "color-mix(in srgb, currentColor 12%, transparent)"
            horizontalRule = border
            codeBlockText = "CanvasText"
            codeComment = codeBlockText
            codeKeyword = codeBlockText
            codeString = codeBlockText
            codeNumber = codeBlockText
            codeType = codeBlockText
            codeFunction = codeBlockText
            codeOperator = codeBlockText
            codeTag = codeBlockText
            codeAttribute = codeBlockText
            codeConstant = codeBlockText
            return
        }

        let preview = theme.preview
        let code = theme.code
        bodyText = preview.body.hex
        secondaryText = preview.secondaryText.hex
        headingPrimary = preview.headingPrimary.hex
        headingSecondary = preview.headingSecondary.hex
        headingTertiary = preview.headingTertiary.hex
        boldText = preview.bold.hex
        italicText = preview.italic.hex
        strikethroughText = preview.strikethrough.hex
        linkText = preview.link.hex
        listMarker = preview.listMarker.hex
        quoteText = preview.blockquoteText.hex
        quoteAccent = preview.blockquoteIndicator.hex
        border = preview.border.hex
        inlineCodeText = preview.inlineCode.hex
        inlineCodeBackground = preview.inlineCodeBackground.hex
        horizontalRule = preview.horizontalRule.hex
        codeBlockText = code.plain.hex
        codeComment = code.comment.hex
        codeKeyword = code.keyword.hex
        codeString = code.string.hex
        codeNumber = code.number.hex
        codeType = code.type.hex
        codeFunction = code.function.hex
        codeOperator = code.operator.hex
        codeTag = code.type.hex
        codeAttribute = code.property.hex
        codeConstant = code.constant.hex
    }

    func codeColour(for role: MarkdownCodeHighlightRole) -> String {
        switch role {
        case .comment: codeComment
        case .keyword: codeKeyword
        case .string: codeString
        case .number: codeNumber
        case .type: codeType
        case .function: codeFunction
        case .operator: codeOperator
        case .tag: codeTag
        case .attribute: codeAttribute
        case .constant: codeConstant
        }
    }
}
