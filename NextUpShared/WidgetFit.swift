import CoreGraphics
import Foundation

public enum WidgetFit {
    public struct Metrics: Equatable, Sendable {
        public var header: CGFloat
        public var row: CGFloat
        public var groupExtra: CGFloat
        public var footer: CGFloat

        public init(header: CGFloat, row: CGFloat, groupExtra: CGFloat, footer: CGFloat) {
            self.header = header
            self.row = row
            self.groupExtra = groupExtra
            self.footer = footer
        }
    }

    public struct Choice: Equatable, Sendable {
        public var shown: Int
        public var more: Int

        public init(shown: Int, more: Int) {
            self.shown = shown
            self.more = more
        }
    }

    /// 在固定高度里放下完整的行。放不下的部分折成一行「还有 N 项」，不把最后一行裁成半截。
    /// `groupStarts[i]` 为真时，第 i 行上方有分组线，行会更高。
    public static func choose(
        rowCount: Int,
        total: Int,
        groupStarts: [Bool],
        height: CGFloat,
        metrics: Metrics
    ) -> Choice {
        let unfinished = max(0, total)
        let available = max(0, rowCount)
        for shown in stride(from: available, through: 0, by: -1) {
            let more = max(0, unfinished - shown)
            let needed = self.height(shown: shown, groupStarts: groupStarts, includeFooter: more > 0, metrics: metrics)
            if needed <= height {
                return Choice(shown: shown, more: more)
            }
        }
        return Choice(shown: 0, more: unfinished)
    }

    public static func height(shown: Int, groupStarts: [Bool], includeFooter: Bool, metrics: Metrics) -> CGFloat {
        var total = metrics.header
        for index in 0..<max(0, shown) {
            total += metrics.row
            if groupStarts.indices.contains(index), groupStarts[index] {
                total += metrics.groupExtra
            }
        }
        if includeFooter {
            total += metrics.footer
        }
        return total
    }
}
