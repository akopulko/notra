import Foundation

/// Describes the native text replacement that produced the newest editor string.
struct MarkdownTextEdit {
    let range: NSRange
    let replacementUTF16Length: Int
}
