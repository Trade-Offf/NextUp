import XCTest
@testable import NextUpShared

final class AppIdentityTests: XCTestCase {
    func testPlaceholdersMatchXcconfig() throws {
        let text = try String(contentsOf: xcconfigURL(), encoding: .utf8)
        let values = assignments(in: text)

        XCTAssertEqual(values["NEXTUP_APP_BUNDLE_ID"], AppIdentity.placeholderAppBundleID)
        XCTAssertEqual(values["NEXTUP_WIDGET_BUNDLE_ID"], AppIdentity.placeholderWidgetBundleID)
        XCTAssertEqual(values["NEXTUP_APP_GROUP_ID"], AppIdentity.placeholderAppGroupID)
        XCTAssertEqual(values["NEXTUP_URL_SCHEME"], AppIdentity.placeholderURLScheme)
        XCTAssertEqual(values["NEXTUP_WIDGET_KIND"], AppIdentity.placeholderWidgetKind)
        XCTAssertEqual(values["MACOSX_DEPLOYMENT_TARGET"], "15.0")
    }

    func testMissingOrBlankInfoValuesAreNil() {
        XCTAssertNil(AppIdentity.string(for: AppIdentity.appGroupInfoKey, in: [:]))
        XCTAssertNil(AppIdentity.string(for: AppIdentity.urlSchemeInfoKey, in: [
            AppIdentity.urlSchemeInfoKey: "   "
        ]))
    }

    func testReadsInjectedInfoValues() {
        let info: [String: Any] = [
            AppIdentity.appGroupInfoKey: " group.custom.nextup ",
            AppIdentity.urlSchemeInfoKey: "customnextup",
            AppIdentity.widgetKindInfoKey: "CustomKind"
        ]

        XCTAssertEqual(AppIdentity.string(for: AppIdentity.appGroupInfoKey, in: info), "group.custom.nextup")
        XCTAssertEqual(AppIdentity.string(for: AppIdentity.urlSchemeInfoKey, in: info), "customnextup")
        XCTAssertEqual(AppIdentity.string(for: AppIdentity.widgetKindInfoKey, in: info), "CustomKind")
    }

    private func xcconfigURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/NextUp.xcconfig")
    }

    private func assignments(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            result[String(key)] = String(value)
        }
        return result
    }
}
