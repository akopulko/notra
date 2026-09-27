import Foundation

/// Semantic Markdown roles used to apply editor syntax colors.
enum MarkdownHighlightRole: Equatable {
    case headingMarker
    case headingText(level: Int)
    case strongMarker
    case strongText
    case emphasisMarker
    case emphasisText
    case strikethroughMarker
    case strikethroughText
    case inlineCodeMarker
    case inlineCodeText
    case codeFence
    case codeLanguageIdentifier
    case quoteMarker
    case quoteText
    case listMarker
    case linkText
    case linkDestination
    case linkMarker
    case thematicBreak
    case escapedCharacter
    case tableMarker
    case tableHeader
    case tableDelimiter
    case tableBody
    case codeComment
    case codeKeyword
    case codeString
    case codeNumber
    case codeType
    case codeFunction
    case codeOperator
    case codeTag
    case codeAttribute
    case codeConstant
}

extension MarkdownHighlightRole {
    var codeRole: MarkdownCodeHighlightRole? {
        switch self {
        case .codeComment: .comment
        case .codeKeyword: .keyword
        case .codeString: .string
        case .codeNumber: .number
        case .codeType: .type
        case .codeFunction: .function
        case .codeOperator: .operator
        case .codeTag: .tag
        case .codeAttribute: .attribute
        case .codeConstant: .constant
        default: nil
        }
    }

    init(codeRole: MarkdownCodeHighlightRole) {
        switch codeRole {
        case .comment: self = .codeComment
        case .keyword: self = .codeKeyword
        case .string: self = .codeString
        case .number: self = .codeNumber
        case .type: self = .codeType
        case .function: self = .codeFunction
        case .operator: self = .codeOperator
        case .tag: self = .codeTag
        case .attribute: self = .codeAttribute
        case .constant: self = .codeConstant
        }
    }
}
