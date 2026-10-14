import CoreGraphics
import Foundation
import SwiftUI

public enum NextUpChrome {
    public struct Stop: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public struct Surface: Equatable, Sendable {
        public var top: Stop
        public var middle: Stop
        public var bottom: Stop
        public var highlightOpacity: Double

        public init(top: Stop, middle: Stop, bottom: Stop, highlightOpacity: Double) {
            self.top = top
            self.middle = middle
            self.bottom = bottom
            self.highlightOpacity = highlightOpacity
        }
    }

    public static let taskSize: CGFloat = 15
    public static let dateSize: CGFloat = 12
    public static let hairline: CGFloat = 0.5
    public static let hairlineOpacity: Double = 0.14
    public static let highlightHeight: CGFloat = 22

    public static let widgetHeaderGap: CGFloat = 6
    public static let widgetDividerTop: CGFloat = 4
    public static let widgetDividerBottom: CGFloat = 3
    public static let widgetRowGap: CGFloat = 4
    public static let widgetGroupRowGap: CGFloat = 2
    public static let widgetIndent: CGFloat = 16

    public static let windowRowPadding: CGFloat = 8
    public static let windowIndent: CGFloat = 34

    /// 设置分组和浮层。比系统小容器收一档，短卡片不会变成胶囊。
    public static let containerRadius: CGFloat = 8

    public static let pressScale: CGFloat = 0.96
    public static let liftScale: CGFloat = 1.02
    public static let parentCheckStart: CGFloat = 0.9
    public static let parentCheckDelay: TimeInterval = 0.05
    public static let dragThreshold: CGFloat = 8

    public static var press: Animation { .snappy(duration: 0.22) }
    public static var settle: Animation { .snappy }
    public static var lift: Animation { .snappy(duration: 0.28) }

    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    public static func perform(_ animation: Animation, reduceMotion: Bool, _ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(animation, changes)
        }
    }

    public static func plainTitle(_ title: String) -> String {
        title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\u{2028}", with: " ")
            .replacingOccurrences(of: "\u{2029}", with: " ")
    }

    public static func surface(window: Bool, dark: Bool) -> Surface {
        if window {
            return dark ? windowDark : windowLight
        }
        return dark ? cardDark : cardLight
    }

    private static let cardLight = Surface(
        top: Stop(red: 0.94, green: 0.95, blue: 0.96),
        middle: Stop(red: 0.78, green: 0.80, blue: 0.83),
        bottom: Stop(red: 0.86, green: 0.88, blue: 0.90),
        highlightOpacity: 0.55
    )

    private static let cardDark = Surface(
        top: Stop(red: 0.24, green: 0.25, blue: 0.27),
        middle: Stop(red: 0.14, green: 0.15, blue: 0.16),
        bottom: Stop(red: 0.18, green: 0.19, blue: 0.20),
        highlightOpacity: 0.16
    )

    private static let windowLight = Surface(
        top: Stop(red: 0.97, green: 0.975, blue: 0.98),
        middle: Stop(red: 0.93, green: 0.935, blue: 0.945),
        bottom: Stop(red: 0.95, green: 0.955, blue: 0.965),
        highlightOpacity: 0.35
    )

    private static let windowDark = Surface(
        top: Stop(red: 0.22, green: 0.23, blue: 0.25),
        middle: Stop(red: 0.16, green: 0.17, blue: 0.18),
        bottom: Stop(red: 0.18, green: 0.19, blue: 0.20),
        highlightOpacity: 0.10
    )
}
