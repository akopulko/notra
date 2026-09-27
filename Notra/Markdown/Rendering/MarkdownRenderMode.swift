import Foundation

/// Distinguishes interactive preview rendering from the layout constraints used for PDF export.
enum MarkdownRenderMode: Equatable, Sendable {
    case preview
    case pdf
}
