import Foundation

public enum TodoClearing {
    public enum Scope: Equatable, Sendable {
        /// 今天写入的任务。今天新建的父任务连同子任务一起删；更早的父任务留下。
        case writtenToday
        /// 文档里的每一项。
        case everything
    }

    public static func removalIDs(in items: [TodoItem], scope: Scope, now: Date, calendar: Calendar) -> Set<UUID> {
        switch scope {
        case .everything:
            return Set(items.map(\.id))
        case .writtenToday:
            let seeds = items.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
            var remove = Set(seeds.map(\.id))
            var grew = true
            while grew {
                grew = false
                for item in items {
                    guard let parentID = item.parentID, remove.contains(parentID), !remove.contains(item.id) else { continue }
                    remove.insert(item.id)
                    grew = true
                }
            }
            return remove
        }
    }
}
