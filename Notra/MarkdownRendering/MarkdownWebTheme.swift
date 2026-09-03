import Foundation

/// Maps Notra's semantic syntax palette to the CSS roles used by the WebKit renderer.
///
/// Normal prose and unclassified fenced code deliberately retain the system text colour.
/// The native renderer applies syntax colours only to recognised code spans, while inline
/// code uses the palette's dedicated code colour.
struct MarkdownWebTheme {
    let bodyText = "CanvasText"
    let codeBlockText = "CanvasText"
    let headingText: String
    let linkText: String
    let markerText: String
    let quoteAccent: String
    let border: String
    let inlineCodeText: String
    let codeComment: String
    let codeKeyword: String
    let codeString: String
    let codeNumber: String
    let codeType: String
    let codeFunction: String
    let codeOperator: String
    let codeTag: String
    let codeAttribute: String

    init(syntaxTheme: MarkdownHighlightTheme?) {
        headingText = syntaxTheme?.heading.hex ?? bodyText
        linkText = syntaxTheme?.link.hex ?? "LinkText"
        markerText = syntaxTheme?.marker.hex ?? "GrayText"
        quoteAccent = syntaxTheme?.quote.hex ?? markerText
        border = syntaxTheme?.marker.hex ?? "#A0A0A0"
        inlineCodeText = syntaxTheme?.code.hex ?? bodyText
        codeComment = syntaxTheme?.codeComment.hex ?? codeBlockText
        codeKeyword = syntaxTheme?.codeKeyword.hex ?? codeBlockText
        codeString = syntaxTheme?.codeString.hex ?? codeBlockText
        codeNumber = syntaxTheme?.codeNumber.hex ?? codeBlockText
        codeType = syntaxTheme?.codeType.hex ?? codeBlockText
        codeFunction = syntaxTheme?.codeFunction.hex ?? codeBlockText
        codeOperator = syntaxTheme?.codeOperator.hex ?? codeBlockText
        codeTag = syntaxTheme?.codeTag.hex ?? codeBlockText
        codeAttribute = syntaxTheme?.codeAttribute.hex ?? codeBlockText
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
        }
    }
}
