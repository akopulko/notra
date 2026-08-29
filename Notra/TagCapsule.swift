import SwiftUI

/// Displays one removable note tag with the same compact styling in both platforms.
struct TagCapsule: View {
    enum Size {
        case compact
        case regular
    }

    enum Style {
        case standard
        case previewOverlay
    }

    @Environment(\.colorScheme) private var colorScheme
    let tag: NoteTag
    var size: Size = .regular
    var style: Style = .standard
    var removeAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            if let removeAction {
                Button {
                    removeAction()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .fontWeight(.medium)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Remove tag \(tag.displayName)")
            }

            Text(tag.prefixedDisplayName)
                .font(font)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(backgroundStyle, in: Capsule())
        .overlay {
            Capsule()
                .stroke(strokeStyle, lineWidth: 0.5)
        }
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        .accessibilityElement(children: removeAction == nil ? .combine : .contain)
        .accessibilityLabel("Tag \(tag.displayName)")
    }

    private var font: Font {
        switch (style, size) {
        case (.previewOverlay, _):
            .callout
        case (.standard, .compact):
            .body.weight(.medium)
        case (.standard, .regular):
            .callout.weight(.medium)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        AnyShapeStyle(Color.accentColor.opacity(backgroundOpacity))
    }

    private var strokeStyle: Color {
        switch style {
        case .standard:
            Color.white.opacity(0.24)
        case .previewOverlay:
            if colorScheme == .dark {
                Color.white.opacity(0.24)
            } else {
                Color.white.opacity(0.3)
            }
        }
    }

    /// Preserves each tag presentation's existing transparency while changing the base colour.
    private var backgroundOpacity: Double {
        switch style {
        case .standard:
            0.82
        case .previewOverlay:
            colorScheme == .dark ? 0.58 : 0.72
        }
    }

    private var shadowColor: Color {
        switch style {
        case .standard:
            Color.clear
        case .previewOverlay:
            if colorScheme == .dark {
                Color.black.opacity(0.26)
            } else {
                Color.black.opacity(0.14)
            }
        }
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .standard:
            0
        case .previewOverlay:
            5
        }
    }

    private var shadowY: CGFloat {
        switch style {
        case .standard:
            0
        case .previewOverlay:
            1
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .compact:
            10
        case .regular:
            12
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .compact:
            5
        case .regular:
            6
        }
    }
}

/// Wraps tag capsules into rows while reporting the height needed by its parent.
struct TagFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        return CGSize(
            width: rows.width,
            height: rows.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? bounds.width

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = rowWidth == 0 ? size.width : rowWidth + horizontalSpacing + size.width

            if rowWidth > 0, proposedWidth > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + verticalSpacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = proposedWidth
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return (totalWidth, totalHeight)
    }
}
