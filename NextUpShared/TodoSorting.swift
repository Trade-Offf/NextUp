import Foundation

public struct WidgetStats: Equatable, Sendable {
    public var unfinished: Int
    public var overdue: Int
    public var today: Int
    public var upcoming: Int
    public var undated: Int

    public static let zero = WidgetStats(unfinished: 0, overdue: 0, today: 0, upcoming: 0, undated: 0)

    public init(unfinished: Int, overdue: Int, today: Int, upcoming: Int, undated: Int) {
        self.unfinished = unfinished
        self.overdue = overdue
        self.today = today
        self.upcoming = upcoming
        self.undated = undated
    }
}

public enum TodoSorting {
    public static func widgetStats(_ items: [TodoItem], now: Date, calendar: Calendar) -> WidgetStats {
        var stats = WidgetStats.zero
        for item in items where item.status != .done {
            stats.unfinished += 1
            switch DueDate.bucket(item.dueDate, now: now, calendar: calendar) {
            case .overdue: stats.overdue += 1
            case .today: stats.today += 1
            case .upcoming: stats.upcoming += 1
            case .undated: stats.undated += 1
            }
        }
        return stats
    }

    public static func incompleteCount(_ items: [TodoItem]) -> Int {
        items.reduce(into: 0) { count, item in
            if item.status != .done { count += 1 }
        }
    }

    public static func incomplete(_ items: [TodoItem], now: Date, calendar: Calendar) -> [TodoItem] {
        items
            .filter { $0.status != .done }
            .sorted { isOrderedBefore($0, $1, now: now, calendar: calendar) }
    }

    public static func widgetItems(_ items: [TodoItem], limit: Int = 3, now: Date, calendar: Calendar) -> [TodoItem] {
        let topLevel = items.filter { $0.parentID == nil }
        return Array(incomplete(topLevel, now: now, calendar: calendar).prefix(max(0, limit)))
    }

    public static func grouped(_ items: [TodoItem], now: Date, calendar: Calendar) -> (todo: [TodoItem], waiting: [TodoItem], done: [TodoItem]) {
        let open = incomplete(items, now: now, calendar: calendar)
        let done = items
            .filter { $0.status == .done }
            .sorted { lhs, rhs in
                let left = lhs.completedAt ?? lhs.updatedAt
                let right = rhs.completedAt ?? rhs.updatedAt
                if left != right { return left > right }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        return (
            open.filter { $0.status == .todo },
            open.filter { $0.status == .waiting },
            done
        )
    }

    public static func isOrderedBefore(_ lhs: TodoItem, _ rhs: TodoItem, now: Date, calendar: Calendar) -> Bool {
        let leftStatus = statusRank(lhs.status)
        let rightStatus = statusRank(rhs.status)
        if leftStatus != rightStatus { return leftStatus < rightStatus }

        let leftBucket = DueDate.bucket(lhs.dueDate, now: now, calendar: calendar)
        let rightBucket = DueDate.bucket(rhs.dueDate, now: now, calendar: calendar)
        if leftBucket != rightBucket { return leftBucket.rawValue < rightBucket.rawValue }

        if leftBucket == .overdue || leftBucket == .upcoming {
            let leftDate = lhs.dueDate ?? ""
            let rightDate = rhs.dueDate ?? ""
            if leftDate != rightDate { return leftDate < rightDate }
        }

        if leftBucket == .undated, lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func statusRank(_ status: TodoStatus) -> Int {
        switch status {
        case .todo: return 0
        case .waiting: return 1
        case .done: return 2
        }
    }
}
