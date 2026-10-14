import XCTest
@testable import NextUpShared

final class DueDateTests: XCTestCase {
    func testRejectsImpossibleAndNonCalendarDates() {
        let calendar = gregorian("Asia/Shanghai")
        XCTAssertNil(DueDate.canonical("2026-02-31", calendar: calendar))
        XCTAssertNil(DueDate.canonical("2026-13-01", calendar: calendar))
        XCTAssertNil(DueDate.canonical("2026-00-10", calendar: calendar))
        XCTAssertNil(DueDate.canonical("2026/10/12", calendar: calendar))
        XCTAssertNil(DueDate.canonical("2026-10-12T00:00:00Z", calendar: calendar))
        XCTAssertEqual(DueDate.canonical(" 2026-10-14 ", calendar: calendar), "2026-10-14")
        XCTAssertNil(DueDate.canonical("   ", calendar: calendar))
    }

    func testComparesCalendarDaysInsteadOfUTCInstants() {
        let losAngeles = gregorian("America/Los_Angeles")
        let due = "2026-10-12"

        let stillPreviousEvening = date(2026, 10, 11, 20, 0, calendar: losAngeles)
        XCTAssertEqual(DueDate.bucket(due, now: stillPreviousEvening, calendar: losAngeles), .upcoming)

        let justAfterLocalMidnight = date(2026, 10, 12, 0, 30, calendar: losAngeles)
        XCTAssertEqual(DueDate.bucket(due, now: justAfterLocalMidnight, calendar: losAngeles), .today)

        let nextLocalMorning = date(2026, 10, 13, 0, 5, calendar: losAngeles)
        XCTAssertEqual(DueDate.bucket(due, now: nextLocalMorning, calendar: losAngeles), .overdue)
    }

    func testAuxiliaryTextFollowsStatusAndDueBucket() {
        let calendar = gregorian("Asia/Shanghai")
        let now = date(2026, 10, 12, 9, 0, calendar: calendar)

        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .todo, dueDate: "2026-10-11", now: now, calendar: calendar, language: .zhHans),
            TaskAuxiliary(text: "已逾期", emphasis: .overdue)
        )
        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .todo, dueDate: "2026-10-12", now: now, calendar: calendar, language: .zhHans),
            TaskAuxiliary(text: "今天", emphasis: .neutral)
        )
        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .todo, dueDate: "2026-10-14", now: now, calendar: calendar, language: .zhHans),
            TaskAuxiliary(text: "10/14", emphasis: .neutral)
        )
        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .todo, dueDate: nil, now: now, calendar: calendar, language: .zhHans).text,
            nil
        )
        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .waiting, dueDate: nil, now: now, calendar: calendar, language: .zhHans).text,
            "等待反馈"
        )
        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .waiting, dueDate: "2026-10-11", now: now, calendar: calendar, language: .zhHans).text,
            "已逾期"
        )
        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .todo, dueDate: "2026-10-11", now: now, calendar: calendar, language: .english).text,
            "Overdue"
        )
    }

    func testNextMidnightUsesLocalCalendar() throws {
        let calendar = gregorian("Asia/Shanghai")
        let now = date(2026, 10, 12, 23, 30, calendar: calendar)
        let midnight = DueDate.nextLocalMidnight(after: now, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: midnight)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 10)
        XCTAssertEqual(parts.day, 13)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 0)
    }

    func testClockDeadlineBecomesOverdueAtThatMinute() {
        let calendar = gregorian("Asia/Shanghai")
        let before = date(2026, 10, 14, 14, 59, calendar: calendar)
        let atDeadline = date(2026, 10, 14, 15, 0, calendar: calendar)
        let nextMorning = date(2026, 10, 15, 9, 0, calendar: calendar)

        XCTAssertEqual(DueDate.bucket("2026-10-14", time: "15:00", now: before, calendar: calendar), .today)
        XCTAssertEqual(DueDate.bucket("2026-10-14", time: "15:00", now: atDeadline, calendar: calendar), .overdue)
        XCTAssertEqual(DueDate.bucket("2026-10-14", now: atDeadline, calendar: calendar), .today)
        XCTAssertEqual(DueDate.bucket("2026-10-15", time: "10:00", now: atDeadline, calendar: calendar), .upcoming)
        XCTAssertEqual(DueDate.bucket("2026-10-15", time: "10:00", now: nextMorning, calendar: calendar), .today)
        XCTAssertEqual(DueDate.bucket(nil, time: nil, now: before, calendar: calendar), .undated)
        XCTAssertNil(DueDate.canonicalTime("25:00"))
        XCTAssertThrowsError(try TodoItem.normalizeDueTime("25:00")) { error in
            XCTAssertEqual(error as? StoreError, .invalidDueDate)
        }
        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .todo, dueDate: "2026-10-14", dueTime: "15:00", now: before, calendar: calendar, language: .zhHans).text,
            "15:00"
        )
        XCTAssertEqual(
            TaskAuxiliaryText.make(status: .todo, dueDate: "2026-10-20", dueTime: "09:30", now: before, calendar: calendar, language: .zhHans).text,
            "10/20 09:30"
        )
    }
}

final class TodoItemTests: XCTestCase {
    func testTitleKeepsInternalWhitespaceAndRejectsBlankOrTooLong() throws {
        XCTAssertEqual(try TodoItem.normalizeTitle("  与 Allen 对齐\n排期  "), "与 Allen 对齐\n排期")
        XCTAssertThrowsError(try TodoItem.normalizeTitle("   \n")) { error in
            XCTAssertEqual(error as? StoreError, .invalidTitle)
        }
        XCTAssertThrowsError(try TodoItem.normalizeTitle(String(repeating: "事", count: 201)))
    }

    func testStatusWritesAndClearsCompletedAt() {
        var item = makeItem(status: .todo)
        let doneAt = Date(timeIntervalSince1970: 1_700_000_000)
        item.applyStatus(.done, now: doneAt)
        XCTAssertEqual(item.status, .done)
        XCTAssertEqual(item.completedAt, doneAt)

        let again = Date(timeIntervalSince1970: 1_700_000_100)
        item.applyStatus(.done, now: again)
        XCTAssertEqual(item.completedAt, doneAt)

        item.applyStatus(.waiting, now: again)
        XCTAssertEqual(item.status, .waiting)
        XCTAssertNil(item.completedAt)
    }

    func testOlderFilesWithoutAClockStillDecode() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"旧任务","status":"todo","sortOrder":0,"createdAt":"2026-10-14T01:00:00Z","updatedAt":"2026-10-14T01:00:00Z","dueDate":"2026-10-14"}
        """
        let item = try StoreCoding.decoder.decode(TodoItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.dueDate, "2026-10-14")
        XCTAssertNil(item.dueTime)
    }
}

enum StoreFixtures {
    static func gregorian(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    static func makeItem(
        title: String = "任务",
        status: TodoStatus = .todo,
        dueDate: String? = nil,
        dueTime: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        id: UUID = UUID()
    ) -> TodoItem {
        TodoItem(
            id: id,
            title: title,
            project: nil,
            assignee: nil,
            dueDate: dueDate,
            dueTime: dueTime,
            status: status,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: status == .done ? createdAt : nil
        )
    }
}

private func gregorian(_ identifier: String) -> Calendar { StoreFixtures.gregorian(identifier) }
private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
    StoreFixtures.date(year, month, day, hour, minute, calendar: calendar)
}
private func makeItem(
    title: String = "任务",
    status: TodoStatus = .todo,
    dueDate: String? = nil,
    sortOrder: Int = 0,
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    id: UUID = UUID()
) -> TodoItem {
    StoreFixtures.makeItem(title: title, status: status, dueDate: dueDate, sortOrder: sortOrder, createdAt: createdAt, id: id)
}
