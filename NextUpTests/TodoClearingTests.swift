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

    func testWidgetStatsSkipsParentsThatHaveChildren() {
        let parent = StoreFixtures.makeItem(title: "父任务", dueDate: "2026-10-14")
        var todayChild = StoreFixtures.makeItem(title: "今天的子任务", dueDate: "2026-10-14")
        todayChild.parentID = parent.id
        var laterChild = StoreFixtures.makeItem(title: "以后的子任务", dueDate: "2026-10-20")
        laterChild.parentID = parent.id
        var doneChild = StoreFixtures.makeItem(title: "完成的子任务", status: .done, dueDate: "2026-10-14")
        doneChild.parentID = parent.id
        let alone = StoreFixtures.makeItem(title: "单独的")

        XCTAssertEqual(
            TodoSorting.widgetStats([parent, todayChild, laterChild, doneChild, alone], now: now, calendar: calendar),
            WidgetStats(unfinished: 3, overdue: 0, today: 1, upcoming: 1, undated: 1)
        )
    }

    func testWidgetStatsFollowClockDeadlinesAndLeaveUndatedItemsAlone() {
        let before = StoreFixtures.date(2026, 10, 14, 14, 59, calendar: calendar)
        let atDeadline = StoreFixtures.date(2026, 10, 14, 15, 0, calendar: calendar)
        let items = [
            StoreFixtures.makeItem(title: "三点", dueDate: "2026-10-14", dueTime: "15:00"),
            StoreFixtures.makeItem(title: "明天上午", dueDate: "2026-10-15", dueTime: "10:00"),
            StoreFixtures.makeItem(title: "没截止"),
            StoreFixtures.makeItem(title: "纯日期今天", dueDate: "2026-10-14")
        ]

        XCTAssertEqual(
            TodoSorting.widgetStats(items, now: before, calendar: calendar),
            WidgetStats(unfinished: 4, overdue: 0, today: 2, upcoming: 1, undated: 1)
        )
        XCTAssertEqual(
            TodoSorting.widgetStats(items, now: atDeadline, calendar: calendar),
            WidgetStats(unfinished: 4, overdue: 1, today: 1, upcoming: 1, undated: 1)
        )
    }

    func testClockDeadlinesIncludeParentLabelsButStatsSkipParents() {
        let parent = StoreFixtures.makeItem(title: "父任务", dueDate: "2026-10-14", dueTime: "15:00")
        var child = StoreFixtures.makeItem(title: "四点", dueDate: "2026-10-14", dueTime: "16:00")
        child.parentID = parent.id
        let past = StoreFixtures.makeItem(title: "已经过点", dueDate: "2026-10-14", dueTime: "08:00")
        let tomorrow = StoreFixtures.makeItem(title: "明天", dueDate: "2026-10-15", dueTime: "10:00")
        let midnight = DueDate.nextLocalMidnight(after: now, calendar: calendar)

        let deadlines = TodoSorting.clockDeadlines(
            [parent, child, past, tomorrow],
            after: now,
            before: midnight,
            calendar: calendar
        )
        XCTAssertEqual(deadlines, [
            DueDate.clockInstant("2026-10-14", time: "15:00", calendar: calendar)!,
            DueDate.clockInstant("2026-10-14", time: "16:00", calendar: calendar)!
        ])
        XCTAssertEqual(
            TodoSorting.widgetStats([parent, child, past, tomorrow], now: now, calendar: calendar),
            WidgetStats(unfinished: 3, overdue: 1, today: 1, upcoming: 1, undated: 0)
        )
    }
}
