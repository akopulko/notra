import SwiftUI

enum MarkdownCodeHighlightRole: Equatable {
    case comment
    case keyword
    case string
    case number
    case type
    case function
    case `operator`
    case tag
    case attribute
}

struct MarkdownCodeHighlightSpan: Equatable {
    let role: MarkdownCodeHighlightRole
    let range: Range<String.Index>
}

enum MarkdownCodeLanguage: Equatable {
    case swift
    case python
    case javascript
    case typescript
    case json
    case html
    case css
    case shell
    case sql
    case yaml
    case cLanguage
    case cpp
    case csharp
    case java
    case go
    case rust
    case kotlin
    case ruby
    case php
    case xml
    case markdown

    init?(fenceTag: String) {
        let tag = fenceTag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let language = Self.languages[tag] else {
            return nil
        }
        self = language
    }

    var usesHashComments: Bool {
        self == .python || self == .shell || self == .ruby || self == .yaml
    }

    var usesSlashComments: Bool {
        switch self {
        case .swift, .javascript, .typescript, .cLanguage, .cpp, .csharp, .java, .go, .rust, .kotlin, .php:
            true
        default:
            false
        }
    }

    var usesSQLComments: Bool {
        self == .sql
    }

    var isMarkup: Bool {
        self == .html || self == .xml
    }

    private static let languages: [String: MarkdownCodeLanguage] = [
        "swift": .swift,
        "python": .python, "py": .python,
        "javascript": .javascript, "js": .javascript, "jsx": .javascript,
        "typescript": .typescript, "ts": .typescript, "tsx": .typescript,
        "json": .json,
        "html": .html, "htm": .html,
        "css": .css,
        "bash": .shell, "sh": .shell, "zsh": .shell, "shell": .shell,
        "sql": .sql,
        "yaml": .yaml, "yml": .yaml,
        "c": .cLanguage,
        "cpp": .cpp, "cxx": .cpp, "cc": .cpp,
        "csharp": .csharp, "cs": .csharp,
        "java": .java,
        "go": .go,
        "rust": .rust, "rs": .rust,
        "kotlin": .kotlin, "kt": .kotlin,
        "ruby": .ruby, "rb": .ruby,
        "php": .php,
        "xml": .xml,
        "markdown": .markdown, "md": .markdown
    ]
}

struct MarkdownCodeSyntaxHighlighter {
    func highlight(
        _ code: String,
        languageTag: String?,
        theme: MarkdownHighlightTheme?,
        baseColor: Color
    ) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = baseColor

        guard let theme, let languageTag, let language = MarkdownCodeLanguage(fenceTag: languageTag) else {
            return attributed
        }

        for span in spans(in: code, language: language) {
            guard let lower = AttributedString.Index(span.range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(span.range.upperBound, within: attributed)
            else {
                continue
            }

            attributed[lower..<upper].foregroundColor = theme.codeColor(for: span.role).color
        }

        return attributed
    }

    func spans(in code: String, language: MarkdownCodeLanguage) -> [MarkdownCodeHighlightSpan] {
        var spans: [MarkdownCodeHighlightSpan] = []
        var current = code.startIndex

        while current < code.endIndex {
            if let commentEnd = commentEnd(in: code, from: current, language: language) {
                spans.append(MarkdownCodeHighlightSpan(role: .comment, range: current..<commentEnd))
                current = commentEnd
            } else if let stringEnd = stringEnd(in: code, from: current) {
                let role: MarkdownCodeHighlightRole = isAttributeString(
                    in: code,
                    range: current..<stringEnd,
                    language: language
                ) ? .attribute : .string
                spans.append(MarkdownCodeHighlightSpan(role: role, range: current..<stringEnd))
                current = stringEnd
            } else if language.isMarkup, code[current] == "<", let tagEnd = tagEnd(in: code, from: current) {
                spans.append(contentsOf: markupSpans(in: code, range: current..<tagEnd))
                current = tagEnd
            } else if code[current].isNumber {
                let end = tokenEnd(in: code, from: current) { $0.isNumber || $0 == "." || $0 == "_" }
                spans.append(MarkdownCodeHighlightSpan(role: .number, range: current..<end))
                current = end
            } else if isWordCharacter(code[current]) {
                let end = tokenEnd(in: code, from: current, matching: isWordCharacter)
                let word = String(code[current..<end])
                if let role = role(for: word, in: code, after: end, language: language) {
                    spans.append(MarkdownCodeHighlightSpan(role: role, range: current..<end))
                }
                current = end
            } else if isOperator(code[current]) {
                let end = code.index(after: current)
                spans.append(MarkdownCodeHighlightSpan(role: .operator, range: current..<end))
                current = end
            } else {
                current = code.index(after: current)
            }
        }

        return spans
    }
}

private extension MarkdownCodeSyntaxHighlighter {
    func commentEnd(in code: String, from index: String.Index, language: MarkdownCodeLanguage) -> String.Index? {
        let next = code.index(after: index)
        let lineEnd = code[index...].firstIndex(of: "\n") ?? code.endIndex

        if language.usesHashComments, code[index] == "#" {
            return lineEnd
        }

        if language.usesSQLComments, code[index] == "-", next < code.endIndex, code[next] == "-" {
            return lineEnd
        }

        if language.usesSlashComments, code[index] == "/", next < code.endIndex, code[next] == "/" {
            return lineEnd
        }

        return nil
    }

    func stringEnd(in code: String, from index: String.Index) -> String.Index? {
        let quote = code[index]
        guard quote == "\"" || quote == "'" || quote == "`" else {
            return nil
        }

        var current = code.index(after: index)
        var isEscaped = false
        while current < code.endIndex {
            let character = code[current]
            if character == quote, !isEscaped {
                return code.index(after: current)
            }
            isEscaped = character == "\\" && !isEscaped
            if character != "\\" {
                isEscaped = false
            }
            current = code.index(after: current)
        }

        return code.endIndex
    }

    func tagEnd(in code: String, from index: String.Index) -> String.Index? {
        guard let closing = code[index...].firstIndex(of: ">") else {
            return nil
        }
        return code.index(after: closing)
    }

    func markupSpans(in code: String, range: Range<String.Index>) -> [MarkdownCodeHighlightSpan] {
        var result: [MarkdownCodeHighlightSpan] = []
        var current = code.index(after: range.lowerBound)
        if current < range.upperBound, code[current] == "/" {
            current = code.index(after: current)
        }
        let tagStart = current
        let tagEnd = tokenEnd(in: code, from: current, matching: isWordCharacter)
        if tagStart < tagEnd {
            result.append(MarkdownCodeHighlightSpan(role: .tag, range: tagStart..<tagEnd))
        }

        current = tagEnd
        while current < range.upperBound {
            if code[current].isWhitespace || code[current] == "/" {
                current = code.index(after: current)
            } else if let stringEnd = stringEnd(in: code, from: current) {
                result.append(MarkdownCodeHighlightSpan(role: .string, range: current..<stringEnd))
                current = stringEnd
            } else if isWordCharacter(code[current]) {
                let end = tokenEnd(in: code, from: current, matching: isWordCharacter)
                result.append(MarkdownCodeHighlightSpan(role: .attribute, range: current..<end))
                current = end
            } else {
                current = code.index(after: current)
            }
        }
        return result
    }

    func role(
        for word: String,
        in code: String,
        after index: String.Index,
        language: MarkdownCodeLanguage
    ) -> MarkdownCodeHighlightRole? {
        if isAttribute(word, in: code, after: index, language: language) {
            return .attribute
        }
        if Self.keywords.contains(word) {
            return .keyword
        }
        if Self.types.contains(word) {
            return .type
        }
        if Self.constants.contains(word) {
            return .number
        }
        if nextSignificantCharacter(in: code, after: index) == "(" {
            return .function
        }
        return nil
    }

    func isAttribute(_ word: String, in code: String, after index: String.Index, language: MarkdownCodeLanguage) -> Bool {
        guard language == .json || language == .yaml || language == .css else {
            return false
        }
        return !word.isEmpty && nextSignificantCharacter(in: code, after: index) == ":"
    }

    func isAttributeString(in code: String, range: Range<String.Index>, language: MarkdownCodeLanguage) -> Bool {
        guard language == .json || language == .yaml else {
            return false
        }
        return nextSignificantCharacter(in: code, after: range.upperBound) == ":"
    }

    func nextSignificantCharacter(in code: String, after index: String.Index) -> Character? {
        var current = index
        while current < code.endIndex, code[current].isWhitespace {
            current = code.index(after: current)
        }
        return current < code.endIndex ? code[current] : nil
    }

    func tokenEnd(
        in code: String,
        from index: String.Index,
        matching predicate: (Character) -> Bool
    ) -> String.Index {
        var current = index
        while current < code.endIndex, predicate(code[current]) {
            current = code.index(after: current)
        }
        return current
    }

    func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    func isOperator(_ character: Character) -> Bool {
        "=+-*/%!<>|&?:".contains(character)
    }

    static let keywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "def", "defer",
        "do", "else", "enum", "export", "extends", "final", "for", "foreach", "func", "function", "guard",
        "if", "import", "in", "interface", "let", "match", "module", "mutating", "new", "package", "private",
        "protected", "protocol", "public", "return", "static", "struct", "switch", "throw", "throws", "trait",
        "try", "typealias", "var", "where", "while", "with", "yield"
    ]
    static let types: Set<String> = [
        "Any", "Array", "Bool", "Character", "Double", "Float", "Int", "Map", "Optional", "Set", "String",
        "UInt", "Void", "boolean", "char", "decimal", "float", "int", "long", "number", "object", "string"
    ]
    static let constants: Set<String> = ["false", "nil", "null", "None", "true", "undefined"]
}
