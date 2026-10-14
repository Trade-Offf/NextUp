import XCTest
@testable import NextUpShared

final class TodoClearingTests: XCTestCase {
    private let calendar = StoreFixtures.gregorian("Asia/Shanghai")
    private lazy var now = StoreFixtures.date(2026, 10, 14, 9, 0, calendar: calendar)
    private lazy var yesterday = StoreFixtures.date(2026, 10, 13, 18, 0, calendar: calendar)

    func testWrittenTodayRemovesTodaysEntriesAndKeepsOlderParents() {
        let parent = StoreFixtures.makeItem(title: "今天的父任务", createdAt: now)
        var olderChild = StoreFixtures.makeItem(title: "更早的子任务", createdAt: yesterday)
        olderChild.parentID = parent.id
        let olderParent = StoreFixtures.makeItem(title: "昨天的父任务", createdAt: yesterday)
        var writtenToday = StoreFixtures.makeItem(title: "今天的子任务", createdAt: now)
        writtenToday.parentID = olderParent.id
        let kept = StoreFixtures.makeItem(title: "昨天单独的", dueDate: "2026-10-15", createdAt: yesterday)

        let ids = TodoClearing.removalIDs(
            in: [parent, olderChild, olderParent, writtenToday, kept],
            scope: .writtenToday,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(ids, Set([parent.id, olderChild.id, writtenToday.id]))
    }

    func testEverythingRemovesOpenAndCompletedItems() {
        let open = StoreFixtures.makeItem(title: "未完成", dueDate: "2026-10-20", createdAt: yesterday)
        let done = StoreFixtures.makeItem(title: "已完成", status: .done, createdAt: yesterday)
        let ids = TodoClearing.removalIDs(
            in: [open, done],
            scope: .everything,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(ids, Set([open.id, done.id]))
    }

    func testBucketsCountOnlyUnfinishedItems() {
        let items = [
            StoreFixtures.makeItem(title: "逾期", dueDate: "2026-10-01"),
            StoreFixtures.makeItem(title: "今天", dueDate: "2026-10-14"),
            StoreFixtures.makeItem(title: "以后", dueDate: "2026-10-20"),
            StoreFixtures.makeItem(title: "未排期"),
            StoreFixtures.makeItem(title: "已完成", status: .done, dueDate: "2026-10-14")
        ]
        XCTAssertEqual(
            TodoSorting.widgetStats(items, now: now, calendar: calendar),
            WidgetStats(unfinished: 4, overdue: 1, today: 1, upcoming: 1, undated: 1)
        )
    }
}
