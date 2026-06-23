import SwiftUI

/// 自动换行的流式布局：子视图从左到右排列，当一行宽度放不下时自动换到下一行。
/// 主要用于把频道标签胶囊排成可换行的多行，避免单行硬截断导致内容看不全。
///
/// 实现基于 SwiftUI 的 `Layout` 协议：
/// - `sizeThatFits` 按给定可用宽度模拟换行，算出整体所需高度；
/// - `placeSubviews` 用同样的换行规则把每个子视图摆到具体坐标。
/// 两者共用一致的"逐个累加宽度、超宽换行"算法，保证测量与摆放结果一致。
struct FlowLayout: Layout {
    /// 同一行内相邻子视图的水平间距。
    var horizontalSpacing: CGFloat = 4
    /// 行与行之间的垂直间距。
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        var isFirstInRow = true

        for size in sizes {
            // 计算把当前元素接到本行后的宽度（首个元素不加间距）。
            let projectedWidth = isFirstInRow
                ? size.width
                : currentRowWidth + horizontalSpacing + size.width

            if !isFirstInRow && projectedWidth > maxWidth {
                // 放不下 → 结算当前行，另起一行。
                totalHeight += currentRowHeight + verticalSpacing
                maxRowWidth = max(maxRowWidth, currentRowWidth)
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth = projectedWidth
                currentRowHeight = max(currentRowHeight, size.height)
            }
            isFirstInRow = false
        }

        // 结算最后一行。
        totalHeight += currentRowHeight
        maxRowWidth = max(maxRowWidth, currentRowWidth)

        let resolvedWidth = maxWidth == .infinity ? maxRowWidth : maxWidth
        return CGSize(width: resolvedWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0
        var isFirstInRow = true

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            // 用"已占用宽度 + 间距 + 本元素宽度"判断是否超出右边界。
            let occupiedWidth = x - bounds.minX
            let projectedWidth = isFirstInRow
                ? size.width
                : occupiedWidth + horizontalSpacing + size.width

            if !isFirstInRow && projectedWidth > maxWidth {
                // 换行：x 回到行首，y 下移一行。
                x = bounds.minX
                y += currentRowHeight + verticalSpacing
                currentRowHeight = 0
                isFirstInRow = true
            }

            if !isFirstInRow {
                x += horizontalSpacing
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )

            x += size.width
            currentRowHeight = max(currentRowHeight, size.height)
            isFirstInRow = false
        }
    }
}
