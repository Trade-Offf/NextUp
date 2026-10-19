import Foundation
import WidgetKit

/// 运行时标识从各 Target 的 Info.plist 读取。
/// plist 中的值由 Config/NextUp.xcconfig 在构建时注入。
/// placeholder 只在 plist 缺少键时兜底，并被测试用来核对 xcconfig，避免两处配置悄悄分叉。
public enum AppIdentity {
    public static let placeholderAppBundleID = "com.binyu.nextupapp"
    public static let placeholderWidgetBundleID = "com.binyu.nextupapp.widget"
    /// macOS 的 App Group 用团队号开头，不需要在开发者网站登记。
    public static let placeholderAppGroupID = "372XT34PQJ.com.binyu.nextupapp"
    public static let placeholderURLScheme = "nextup"
    public static let countWidgetKind = "NextUpCount"
    public static let listWidgetKind = "NextUpList"
    public static let widgetKinds = [countWidgetKind, listWidgetKind]

    public static let appGroupInfoKey = "NextUpAppGroupID"
    public static let urlSchemeInfoKey = "NextUpURLScheme"

    public static func appGroupID(in bundle: Bundle = .main) -> String {
        string(for: appGroupInfoKey, in: bundle) ?? placeholderAppGroupID
    }

    public static func urlScheme(in bundle: Bundle = .main) -> String {
        string(for: urlSchemeInfoKey, in: bundle) ?? placeholderURLScheme
    }

    public static func string(for key: String, in bundle: Bundle) -> String? {
        let info = bundle.infoDictionary ?? [:]
        return string(for: key, in: info)
    }

    public static func string(for key: String, in info: [String: Any]) -> String? {
        guard let value = info[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 时间线默认等到本地午夜才重读文件。数据变了之后从这里刷新，主应用和小组件勾选走同一处。
    /// 全部刷新覆盖已经放在桌面上的卡片，点名刷新覆盖当前两种 kind。旧 kind 不放回画廊。
    public static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        for kind in widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
