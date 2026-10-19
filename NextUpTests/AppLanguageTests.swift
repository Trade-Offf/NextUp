import XCTest
@testable import NextUpShared

final class AppLanguageTests: XCTestCase {
    func testUsesAShippedLanguageFromTheSystemList() {
        XCTAssertEqual(AppLanguage.matching(["zh-Hans-CN"]), .zhHans)
        XCTAssertEqual(AppLanguage.matching(["zh-CN"]), .zhHans)
        XCTAssertEqual(AppLanguage.matching(["en-US"]), .english)
        XCTAssertEqual(AppLanguage.matching(["ja-JP", "zh-Hans"]), .japanese)
        XCTAssertEqual(AppLanguage.matching(["en-AU"]), .englishAU)
        XCTAssertEqual(AppLanguage.matching(["zh-Hant-TW"]), .zhHant)
        XCTAssertEqual(AppLanguage.matching(["zh-TW", "en-US"]), .zhHant)
        XCTAssertEqual(AppLanguage.matching(["zh-HK"]), .zhHant)
        XCTAssertEqual(AppLanguage.matching(["zh-Hans-HK"]), .zhHans)
        XCTAssertEqual(AppLanguage.matching(["fr-FR"]), .french)
        XCTAssertEqual(AppLanguage.matching(["fr-CA", "en-US"]), .french)
    }

    func testFallsBackToEnglishWhenNothingShippedMatches() {
        XCTAssertEqual(AppLanguage.matching(["de-DE"]), .english)
        XCTAssertEqual(AppLanguage.matching(["ko-KR"]), .english)
        XCTAssertEqual(AppLanguage.matching(["ko-KR"]), .english)
    }

    func testEveryLanguageCoversEveryKey() {
        let keys: [Copy.Key] = [.windowTitle, .completed, .composerPlaceholder, .subtask, .add, .addSubtask, .edit, .delete, .title, .menuPlaceholder, .openApp, .quitApp, .allDone, .tapToOpen, .allDoneHint, .readFailed, .readFailedHint, .overdue, .today, .waiting, .settings, .general, .language, .restoreBackup, .ok, .notice, .containerUnavailable, .corrupted, .notFound, .invalidTitle, .invalidDueDate, .writeFailed, .backupUnavailable, .restoreNotNeeded, .restored, .widgetCountName, .widgetCountDescription, .widgetListName, .widgetListDescription, .unrecognizedLink, .missingTask, .undoAdd, .undoComplete, .undoReopen, .undoRename, .undoMove, .undoDeadline, .deadline, .dueToday, .pickDateTime, .clearDeadline, .tasksMenu, .newTask, .selectAllTasks, .selectPrevious, .selectNext, .deleteSelection, .clearCompleted, .toggleDone, .rename, .moveUp, .moveDown, .clearSelection, .pasteHint, .emptyHint, .dataSection, .clearToday, .clearHistory, .cancel, .widgetOpenItems, .widgetUpcoming, .widgetUndated, .showWidgetBadge, .shortcuts, .customizeShortcuts, .pressShortcut, .restoreDefaults, .shortcutDone, .shortcutReserved, .shortcutReplace, .shortcutGroupEdit, .noShortcut, .undoLabel, .redoLabel]
        for language in AppLanguage.allCases {
            for key in keys {
                XCTAssertFalse(Copy.text(key, language).isEmpty, "\(language) is missing \(key)")
            }
        }
        XCTAssertNotEqual(Copy.text(.customizeShortcuts, .englishAU), Copy.text(.customizeShortcuts, .english))
    }

    func testDayFirstLanguagesWriteTheDayBeforeTheMonth() {
        XCTAssertEqual(DueDate.monthDayLabel("2026-10-14", dayFirst: AppLanguage.englishAU.writesDayFirst), "14/10")
        XCTAssertEqual(DueDate.monthDayLabel("2026-10-14", dayFirst: AppLanguage.french.writesDayFirst), "14/10")
        XCTAssertEqual(DueDate.monthDayLabel("2026-10-14", dayFirst: AppLanguage.english.writesDayFirst), "10/14")
        XCTAssertEqual(DueDate.monthDayLabel("2026-10-14", dayFirst: AppLanguage.japanese.writesDayFirst), "10/14")
    }

    func testTextSizeIsRememberedAndDefaultsToMedium() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prefs-\(UUID().uuidString).json")
        AppPreferences.fileOverride = url
        defer {
            AppPreferences.fileOverride = nil
            try? FileManager.default.removeItem(at: url)
        }
        XCTAssertEqual(AppPreferences.textSize(), .medium)
        try AppPreferences.save(.large)
        XCTAssertEqual(AppPreferences.textSize(), .large)
        try AppPreferences.save(AppLanguage.japanese)
        XCTAssertEqual(AppPreferences.textSize(), .large)
        XCTAssertEqual(AppPreferences.chosen(), .japanese)
        XCTAssertEqual(TextSize.small.scale, 0.9)
        XCTAssertEqual(TextSize.large.scale, 1.2)
    }
}
