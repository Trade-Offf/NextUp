import XCTest
@testable import NextUpShared

final class OutlineParserTests: XCTestCase {
    private let calendar = StoreFixtures.gregorian("Asia/Shanghai")
    private let now = StoreFixtures.date(2026, 10, 12, 9, 0, calendar: StoreFixtures.gregorian("Asia/Shanghai"))

    func testSampleOutlineBecomesThreeLevels() {
        let sample = """
        一、I18n AI优化方案
        1. @zizel，等待 i18n 方案回复，再次更新
        2. 完事儿之后拉产品进场

        二、BD后台（10.14 提测）
        1. 跟 @Allen 对齐排期，更新项目管理;
        2. 跟进开发;
        \ta. Admin Lead pool 支持删除
        \tb. Manager dashboard 展示调整

        三、CashBack 功能跟进（10.15 发版）
        1. 等待 @summer反馈，有问题继续跟进
        """
        let roots = OutlineParser.parse(sample, now: now, calendar: calendar)
        XCTAssertEqual(roots.map(\.title), [
            "I18n AI优化方案",
            "BD后台（10.14 提测）",
            "CashBack 功能跟进（10.15 发版）"
        ])
        XCTAssertEqual(roots[0].children.map(\.title), [
            "@zizel，等待 i18n 方案回复，再次更新",
            "完事儿之后拉产品进场"
        ])
        XCTAssertEqual(roots[0].children[0].assignee, "zizel")
        XCTAssertEqual(roots[1].dueDate, "2026-10-14")
        XCTAssertEqual(roots[1].children[0].assignee, "Allen")
        XCTAssertEqual(roots[1].children[1].children.map(\.title), [
            "Admin Lead pool 支持删除",
            "Manager dashboard 展示调整"
        ])
        XCTAssertEqual(roots[2].dueDate, "2026-10-15")
        XCTAssertEqual(roots[2].children[0].assignee, "summer")
        XCTAssertTrue(OutlineParser.looksLikeOutline(sample))
        XCTAssertFalse(OutlineParser.looksLikeOutline("记下一件事"))
    }

    func testOutlinePersistsTheTree() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NextUp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TodoRepository(directory: directory)
        let created = try repository.addOutline("""
        一、方案
        1. 第一步
        \ta. 细节
        """, now: now, calendar: calendar)
        XCTAssertEqual(created.map(\.title), ["方案", "第一步", "细节"])
        XCTAssertNil(created[0].parentID)
        XCTAssertEqual(created[1].parentID, created[0].id)
        XCTAssertEqual(created[2].parentID, created[1].id)
        XCTAssertEqual(created[0].dueDate, nil)
    }
}
