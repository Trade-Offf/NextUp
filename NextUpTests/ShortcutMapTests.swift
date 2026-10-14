import XCTest
@testable import NextUpShared

final class ShortcutMapTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NextUp-prefs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        AppPreferences.fileOverride = directory.appendingPathComponent("preferences.json")
    }

    override func tearDownWithError() throws {
        AppPreferences.fileOverride = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testOldLanguageFileKeepsDefaults() throws {
        let original = #"{"language":"zh-Hans"}"#.data(using: .utf8)!
        try original.write(to: AppPreferences.fileOverride!)
        XCTAssertEqual(AppPreferences.chosen(), .zhHans)
        XCTAssertEqual(AppPreferences.shortcutMap().binding(for: .undo), ShortcutBinding(key: "z", modifiers: [.command]))
        XCTAssertEqual(AppPreferences.shortcutMap().binding(for: .deleteSelection), ShortcutBinding(key: "delete"))
    }

    func testSavingLanguageKeepsShortcuts() throws {
        var map = ShortcutMap()
        map.assign(ShortcutBinding(key: "delete", modifiers: [.command]), to: .deleteSelection)
        try AppPreferences.save(map)
        try AppPreferences.save(.english)
        XCTAssertEqual(AppPreferences.chosen(), .english)
        XCTAssertEqual(
            AppPreferences.shortcutMap().binding(for: .deleteSelection),
            ShortcutBinding(key: "delete", modifiers: [.command])
        )
    }

    func testSavingShortcutsKeepsLanguage() throws {
        try AppPreferences.save(.zhHans)
        var map = ShortcutMap()
        map.clear(.newTask)
        try AppPreferences.save(map)
        XCTAssertEqual(AppPreferences.chosen(), .zhHans)
        XCTAssertNil(AppPreferences.shortcutMap().binding(for: .newTask))
        XCTAssertEqual(AppPreferences.shortcutMap().binding(for: .undo), ShortcutMap.defaults[.undo])
    }

    func testClearedCommandStaysCleared() throws {
        var map = ShortcutMap()
        map.clear(.deleteSelection)
        try AppPreferences.save(map)
        let loaded = AppPreferences.shortcutMap()
        XCTAssertNil(loaded.binding(for: .deleteSelection))
        XCTAssertNotEqual(loaded.binding(for: .deleteSelection), ShortcutMap.defaults[.deleteSelection])
    }

    func testConflictAndReservedKeys() {
        let map = ShortcutMap()
        XCTAssertEqual(map.check(ShortcutBinding(key: "n", modifiers: [.command]), for: .undo), .conflict(.newTask))
        XCTAssertEqual(map.check(ShortcutBinding(key: "q", modifiers: [.command]), for: .newTask), .reserved)
        XCTAssertEqual(map.check(ShortcutBinding(key: ",", modifiers: [.command]), for: .newTask), .reserved)
        XCTAssertEqual(map.check(ShortcutBinding(key: "k", modifiers: [.command]), for: .newTask), .available)
    }

    func testReplaceClearsTheOtherCommand() {
        var map = ShortcutMap()
        let binding = ShortcutBinding(key: "n", modifiers: [.command])
        map.replace(binding, to: .undo, from: .newTask)
        XCTAssertEqual(map.binding(for: .undo), binding)
        XCTAssertNil(map.binding(for: .newTask))
    }

    func testBadShortcutEntryKeepsLanguage() throws {
        let original = #"{"language":"zh-Hans","shortcuts":{"undo":{"key":1},"redo":{"key":"y","modifiers":["command"]}}}"#.data(using: .utf8)!
        try original.write(to: AppPreferences.fileOverride!)
        XCTAssertEqual(AppPreferences.chosen(), .zhHans)
        XCTAssertEqual(AppPreferences.shortcutMap().binding(for: .undo), ShortcutMap.defaults[.undo])
        XCTAssertEqual(AppPreferences.shortcutMap().binding(for: .redo), ShortcutBinding(key: "y", modifiers: [.command]))
        try AppPreferences.save(.english)
        XCTAssertEqual(AppPreferences.chosen(), .english)
        XCTAssertEqual(AppPreferences.shortcutMap().binding(for: .redo), ShortcutBinding(key: "y", modifiers: [.command]))
    }

    func testAssigningTheDefaultDropsTheOverride() throws {
        var map = ShortcutMap()
        map.assign(ShortcutBinding(key: "y", modifiers: [.command]), to: .undo)
        map.assign(ShortcutBinding(key: "z", modifiers: [.command]), to: .undo)
        try AppPreferences.save(map)
        let data = try Data(contentsOf: AppPreferences.fileOverride!)
        let raw = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(raw.contains("undo"))
        XCTAssertEqual(AppPreferences.shortcutMap().binding(for: .undo)?.display, "⌘Z")
    }
}