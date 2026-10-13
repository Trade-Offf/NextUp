import XCTest
@testable import NextUpShared

final class AppLanguageTests: XCTestCase {
    func testUsesAShippedLanguageFromTheSystemList() {
        XCTAssertEqual(AppLanguage.matching(["zh-Hans-CN"]), .zhHans)
        XCTAssertEqual(AppLanguage.matching(["zh-CN"]), .zhHans)
        XCTAssertEqual(AppLanguage.matching(["en-US"]), .english)
        XCTAssertEqual(AppLanguage.matching(["ja-JP", "zh-Hans"]), .zhHans)
    }

    func testFallsBackToEnglishWhenNothingShippedMatches() {
        XCTAssertEqual(AppLanguage.matching(["ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.matching(["zh-Hant-TW"]), .english)
        XCTAssertEqual(AppLanguage.matching(["zh-TW", "en-US"]), .english)
        XCTAssertEqual(AppLanguage.matching(["fr-FR"]), .english)
        XCTAssertNil(AppLanguage.match("zh-HK"))
    }
}
