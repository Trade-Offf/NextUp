import Foundation

/// 运行时标识从各 Target 的 Info.plist 读取。
/// plist 中的值由 Config/NextUp.xcconfig 在构建时注入。
/// placeholder 只在 plist 缺少键时兜底，并被测试用来核对 xcconfig，避免两处配置悄悄分叉。
public enum AppIdentity {
    public static let placeholderAppBundleID = "com.example.nextup"
    public static let placeholderWidgetBundleID = "com.example.nextup.widget"
    public static let placeholderAppGroupID = "group.com.example.nextup"
    public static let placeholderURLScheme = "nextup"
    public static let placeholderWidgetKind = "NextUpWidget"

    public static let appGroupInfoKey = "NextUpAppGroupID"
    public static let urlSchemeInfoKey = "NextUpURLScheme"
    public static let widgetKindInfoKey = "NextUpWidgetKind"

    public static func appGroupID(in bundle: Bundle = .main) -> String {
        string(for: appGroupInfoKey, in: bundle) ?? placeholderAppGroupID
    }

    public static func urlScheme(in bundle: Bundle = .main) -> String {
        string(for: urlSchemeInfoKey, in: bundle) ?? placeholderURLScheme
    }

    public static func widgetKind(in bundle: Bundle = .main) -> String {
        string(for: widgetKindInfoKey, in: bundle) ?? placeholderWidgetKind
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
}
