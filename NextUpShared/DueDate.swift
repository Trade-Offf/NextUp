import Foundation

public enum DueDate {
    public enum Bucket: Int, Equatable, Sendable {
        case overdue = 0
        case today = 1
        case upcoming = 2
        case undated = 3
    }

    public static func canonical(_ raw: String?, calendar: Calendar) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              trimmed.unicodeScalars.allSatisfy({ $0 == "-" || ($0 >= "0" && $0 <= "9") }),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func bucket(_ raw: String?, now: Date, calendar: Calendar) -> Bucket {
        bucket(raw, time: nil, now: now, calendar: calendar)
    }

    public static func bucket(_ raw: String?, time: String?, now: Date, calendar: Calendar) -> Bucket {
        guard let canonical = canonical(raw, calendar: calendar),
              let due = yearMonthDay(canonical),
              let today = yearMonthDay(from: now, calendar: calendar) else {
            return .undated
        }
        if let instant = clockInstant(canonical, time: time, calendar: calendar) {
            if now >= instant { return .overdue }
            if due == today { return .today }
            if due > today { return .upcoming }
            return .overdue
        }
        if due < today { return .overdue }
        if due == today { return .today }
        return .upcoming
    }

    public static func canonicalTime(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2,
              parts[1].count == 2,
              trimmed.unicodeScalars.allSatisfy({ $0 == ":" || ($0 >= "0" && $0 <= "9") }),
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    public static func dayString(from date: Date, calendar: Calendar) -> String? {
        guard let parts = yearMonthDay(from: date, calendar: calendar) else { return nil }
        return String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
    }

    public static func timeString(from date: Date, calendar: Calendar) -> String? {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    public static func clockInstant(_ raw: String?, time: String?, calendar: Calendar) -> Date? {
        guard let canonical = canonical(raw, calendar: calendar),
              let due = yearMonthDay(canonical),
              let clock = clockParts(time) else {
            return nil
        }
        return date(year: due.year, month: due.month, day: due.day, hour: clock.hour, minute: clock.minute, calendar: calendar)
    }

    /// 纯日期用当天结束来比，所以同一天里带钟点的更靠前。
    public static func sortInstant(_ raw: String?, time: String?, calendar: Calendar) -> Date? {
        guard let canonical = canonical(raw, calendar: calendar),
              let due = yearMonthDay(canonical),
              let start = date(year: due.year, month: due.month, day: due.day, hour: 0, minute: 0, calendar: calendar) else {
            return nil
        }
        if let instant = clockInstant(canonical, time: time, calendar: calendar) {
            return instant
        }
        return calendar.date(byAdding: .day, value: 1, to: start)
    }

    public static func monthDayLabel(_ raw: String?) -> String? {
        guard let raw, let parts = yearMonthDay(raw) else { return nil }
        return String(format: "%02d/%02d", parts.month, parts.day)
    }

    public static func nextLocalMidnight(after now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    private static func yearMonthDay(_ raw: String) -> (year: Int, month: Int, day: Int)? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return (year, month, day)
    }

    private static func yearMonthDay(from date: Date, calendar: Calendar) -> (year: Int, month: Int, day: Int)? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return (year, month, day)
    }

    private static func clockParts(_ raw: String?) -> (hour: Int, minute: Int)? {
        guard let canonical = canonicalTime(raw) else { return nil }
        let parts = canonical.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day, resolved.hour == hour, resolved.minute == minute else {
            return nil
        }
        return date
    }
}

public struct TaskAuxiliary: Equatable, Sendable {
    public enum Emphasis: Equatable, Sendable {
        case overdue
        case neutral
    }

    public var text: String?
    public var emphasis: Emphasis

    public init(text: String?, emphasis: Emphasis) {
        self.text = text
        self.emphasis = emphasis
    }
}

public enum TaskAuxiliaryText {
    public static func make(status: TodoStatus, dueDate: String?, dueTime: String? = nil, now: Date, calendar: Calendar, language: AppLanguage = .resolved) -> TaskAuxiliary {
        let bucket = DueDate.bucket(dueDate, time: dueTime, now: now, calendar: calendar)
        switch (status, bucket) {
        case (.done, _):
            return TaskAuxiliary(text: nil, emphasis: .neutral)
        case (_, .overdue):
            return TaskAuxiliary(text: Copy.text(.overdue, language), emphasis: .overdue)
        case (_, .today):
            if let time = DueDate.canonicalTime(dueTime) {
                return TaskAuxiliary(text: time, emphasis: .neutral)
            }
            return TaskAuxiliary(text: Copy.text(.today, language), emphasis: .neutral)
        case (_, .upcoming):
            if let day = DueDate.monthDayLabel(dueDate), let time = DueDate.canonicalTime(dueTime) {
                return TaskAuxiliary(text: "\(day) \(time)", emphasis: .neutral)
            }
            return TaskAuxiliary(text: DueDate.monthDayLabel(dueDate), emphasis: .neutral)
        case (.waiting, .undated):
            return TaskAuxiliary(text: Copy.text(.waiting, language), emphasis: .neutral)
        case (.todo, .undated):
            return TaskAuxiliary(text: nil, emphasis: .neutral)
        }
    }
}
