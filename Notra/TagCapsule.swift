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
        case sidebar
    }

    let tag: NoteTag
    var size: Size = .regular
    var style: Style = .standard
    var displayText: String?
    var removeAction: (() -> Void)?

    init(
        tag: NoteTag,
        size: Size = .regular,
        style: Style = .standard,
        displayText: String? = nil,
        removeAction: (() -> Void)? = nil
    ) {
        self.tag = tag
        self.size = size
        self.style = style
        self.displayText = displayText
        self.removeAction = removeAction
    }

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
                .accessibilityLabel("Remove tag \(tag.displayName)")
            }

            Text(displayText ?? tag.prefixedDisplayName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .modifier(TagCapsuleAppearance(size: size, style: style))
        .accessibilityElement(children: removeAction == nil ? .combine : .contain)
        .accessibilityLabel("Tag \(tag.displayName)")
    }
}

struct TagCapsuleAppearance: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let size: TagCapsule.Size
    let style: TagCapsule.Style

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(tagColors.foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundStyle, in: roundedRectangle)
            .overlay {
                roundedRectangle
                    .stroke(strokeStyle, lineWidth: 0.5)
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var font: Font {
        switch (style, size) {
        case (.previewOverlay, _):
            .caption2
        case (.sidebar, _):
            .body
        case (.standard, .compact), (.standard, .regular):
            .caption2.weight(.medium)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        AnyShapeStyle(tagColors.backgroundColor.opacity(backgroundOpacity))
    }

    private var roundedRectangle: RoundedRectangle {
        RoundedRectangle(cornerRadius: style == .standard ? 3 : 4, style: .continuous)
    }

    private var strokeStyle: Color {
        switch style {
        case .standard:
            Color.white.opacity(0.24)
        case .previewOverlay, .sidebar:
            if colorScheme == .dark {
                Color.white.opacity(0.24)
            } else {
                Color.white.opacity(0.3)
            }
        }
    }

    private var shadowColor: Color {
        switch style {
        case .standard:
            Color.clear
        case .previewOverlay, .sidebar:
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
        case .previewOverlay, .sidebar:
            5
        }
    }

    private var shadowY: CGFloat {
        switch style {
        case .standard:
            0
        case .previewOverlay, .sidebar:
            1
        }
    }

    private var tagColors: MarkdownTagColors {
        // Hashtags follow the OS appearance, independently of preview body theming.
        MarkdownTheme.preferred(for: colorScheme).previewHashtagColors
    }

    /// Keeps overlay hashtags translucent while improving contrast against preview content.
    private var backgroundOpacity: Double {
        switch style {
        case .standard, .sidebar:
            1
        case .previewOverlay:
            colorScheme == .dark ? 0.73 : 0.87
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .compact:
            8
        case .regular:
            10
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .compact:
            4
        case .regular:
            5
        }
    }
}

/// Wraps tag capsules into rows while reporting the height needed by its parent.
struct TagFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    struct Cache {
        var intrinsicSizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(intrinsicSizes: intrinsicSizes(for: subviews))
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.intrinsicSizes = intrinsicSizes(for: subviews)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let maxWidth = finiteWidth(proposal.width) ?? .infinity
        let sizes = sizedSubviews(for: subviews, cache: &cache, maxWidth: maxWidth)
        let rows = rows(for: sizes, maxWidth: maxWidth)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let maxWidth = finiteWidth(proposal.width) ?? bounds.width
        let sizes = sizedSubviews(for: subviews, cache: &cache, maxWidth: maxWidth)
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func intrinsicSizes(for subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    private func cachedIntrinsicSizes(for subviews: Subviews, cache: inout Cache) -> [CGSize] {
        guard cache.intrinsicSizes.count == subviews.count else {
            cache.intrinsicSizes = intrinsicSizes(for: subviews)
            return cache.intrinsicSizes
        }
        return cache.intrinsicSizes
    }

    private func sizedSubviews(for subviews: Subviews, cache: inout Cache, maxWidth: CGFloat) -> [CGSize] {
        let sizes = cachedIntrinsicSizes(for: subviews, cache: &cache)
        guard maxWidth.isFinite else { return sizes }
        return zip(subviews, sizes).map { subview, size in
            size.width > maxWidth
                ? subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                : size
        }
    }

    private func finiteWidth(_ width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite else { return nil }
        return width
    }

    private func rows(for sizes: [CGSize], maxWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for size in sizes {
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
