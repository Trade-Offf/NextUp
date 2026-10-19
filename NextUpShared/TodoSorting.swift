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
        let parents = Set(items.compactMap(\.parentID))
        var stats = WidgetStats.zero
        for item in items where item.status != .done && !parents.contains(item.id) {
            stats.unfinished += 1
            switch DueDate.bucket(item.dueDate, time: item.dueTime, now: now, calendar: calendar) {
            case .overdue: stats.overdue += 1
            case .today: stats.today += 1
            case .upcoming: stats.upcoming += 1
            case .undated: stats.undated += 1
            }
        }
        return stats
    }

    /// 午夜前会到点的未完成任务。父任务不进统计，但大号列表仍显示它的行尾，所以这里包含父任务。
    public static func clockDeadlines(_ items: [TodoItem], after now: Date, before limit: Date, calendar: Calendar) -> [Date] {
        var seen: Set<Int> = []
        var instants: [Date] = []
        for item in items where item.status != .done {
            guard let instant = DueDate.clockInstant(item.dueDate, time: item.dueTime, calendar: calendar),
                  instant > now,
                  instant < limit else {
                continue
            }
            let key = Int(instant.timeIntervalSince1970.rounded())
            if seen.insert(key).inserted {
                instants.append(instant)
            }
        }
        return instants.sorted()
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

    public static func isOrderedBefore(_ lhs: TodoItem, _ rhs: TodoItem, now: Date, calendar: Calendar) -> Bool {
        let leftStatus = statusRank(lhs.status)
        let rightStatus = statusRank(rhs.status)
        if leftStatus != rightStatus { return leftStatus < rightStatus }

        let leftBucket = DueDate.bucket(lhs.dueDate, time: lhs.dueTime, now: now, calendar: calendar)
        let rightBucket = DueDate.bucket(rhs.dueDate, time: rhs.dueTime, now: now, calendar: calendar)
        if leftBucket != rightBucket { return leftBucket.rawValue < rightBucket.rawValue }

        if leftBucket == .overdue || leftBucket == .today || leftBucket == .upcoming {
            let leftDeadline = DueDate.sortInstant(lhs.dueDate, time: lhs.dueTime, calendar: calendar)
            let rightDeadline = DueDate.sortInstant(rhs.dueDate, time: rhs.dueTime, calendar: calendar)
            if let leftDeadline, let rightDeadline, leftDeadline != rightDeadline {
                return leftDeadline < rightDeadline
            }
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
