import XCTest
@testable import NextUpShared

final class TodoSortingTests: XCTestCase {
    private let calendar = StoreFixtures.gregorian("Asia/Shanghai")
    private lazy var now = StoreFixtures.date(2026, 10, 12, 9, 0, calendar: calendar)

    func testTodoComesBeforeWaitingAndDueBucketsFollowTheSpec() {
        let overdueWaiting = StoreFixtures.makeItem(title: "逾期等待", status: .waiting, dueDate: "2026-10-01", createdAt: stamp(1))
        let futureTodo = StoreFixtures.makeItem(title: "未来", dueDate: "2026-10-20", createdAt: stamp(2))
        let todayTodo = StoreFixtures.makeItem(title: "今天", dueDate: "2026-10-12", createdAt: stamp(3))
        let earlierOverdue = StoreFixtures.makeItem(title: "更早逾期", dueDate: "2026-10-01", createdAt: stamp(4))
        let laterOverdue = StoreFixtures.makeItem(title: "较晚逾期", dueDate: "2026-10-10", createdAt: stamp(5))
        let undatedEarly = StoreFixtures.makeItem(title: "无日期靠前", sortOrder: 1, createdAt: stamp(7))
        let undatedLate = StoreFixtures.makeItem(title: "无日期靠后", sortOrder: 2, createdAt: stamp(6))
        let done = StoreFixtures.makeItem(title: "已完成", status: .done, dueDate: "2026-10-01", createdAt: stamp(0))

        let ordered = TodoSorting.incomplete(
            [undatedLate, done, futureTodo, overdueWaiting, todayTodo, undatedEarly, laterOverdue, earlierOverdue],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(ordered.map(\.title), [
            "更早逾期",
            "较晚逾期",
            "今天",
            "未来",
            "无日期靠前",
            "无日期靠后",
            "逾期等待"
        ])
        XCTAssertEqual(TodoSorting.incompleteCount(ordered + [done]), 7)
    }

    func testSameDueDateUsesCreatedAtThenIdentifier() {
        let older = StoreFixtures.makeItem(
            title: "先创建",
            dueDate: "2026-10-01",
            sortOrder: 9,
            createdAt: stamp(2),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        let newer = StoreFixtures.makeItem(
            title: "后创建",
            dueDate: "2026-10-01",
            sortOrder: 1,
            createdAt: stamp(3),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let sameMomentLowID = StoreFixtures.makeItem(
            title: "同一时刻较小 ID",
            dueDate: "2026-10-01",
            createdAt: stamp(2),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )

        let ordered = TodoSorting.incomplete(
            [newer, sameMomentLowID, older],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(ordered.map(\.title), ["同一时刻较小 ID", "先创建", "后创建"])
    }

    func testEarlierClockSortsBeforeADateOnlyDeadlineOnTheSameDay() {
        let timed = StoreFixtures.makeItem(title: "上午", dueDate: "2026-10-12", dueTime: "09:30", createdAt: stamp(4))
        let restOfDay = StoreFixtures.makeItem(title: "今天", dueDate: "2026-10-12", createdAt: stamp(1))
        let ordered = TodoSorting.incomplete([restOfDay, timed], now: now, calendar: calendar)
        XCTAssertEqual(ordered.map(\.title), ["上午", "今天"])
    }

    func testWidgetLimitShowsThreeWithoutPaddingAndLetsWaitingFillGaps() {
        let todos = (0..<2).map {
            StoreFixtures.makeItem(title: "待办\($0)", dueDate: "2026-10-1\($0)", createdAt: stamp($0))
        }
        let waiting = StoreFixtures.makeItem(title: "等待", status: .waiting, createdAt: stamp(3))
        let laterTodo = StoreFixtures.makeItem(title: "更晚的待办", dueDate: "2026-12-01", createdAt: stamp(4))

        XCTAssertEqual(
            TodoSorting.widgetItems(todos + [waiting], now: now, calendar: calendar).map(\.title),
            ["待办0", "待办1", "等待"]
        )
        XCTAssertEqual(TodoSorting.incompleteCount(todos + [waiting]), 3)

        let crowded = TodoSorting.widgetItems(todos + [laterTodo, waiting], now: now, calendar: calendar)
        XCTAssertEqual(crowded.map(\.title), ["待办0", "待办1", "更晚的待办"])
        XCTAssertEqual(TodoSorting.incompleteCount(todos + [laterTodo, waiting]), 4)
        XCTAssertEqual(TodoSorting.widgetItems([waiting], now: now, calendar: calendar).count, 1)
    }

    private func stamp(_ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + day))
    }
}
