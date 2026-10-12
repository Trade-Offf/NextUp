import Foundation

public enum TodoStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case waiting
    case done
}

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public static let maxTitleLength = 200

    public let id: UUID
    public var title: String
    public var project: String?
    public var assignee: String?
    public var dueDate: String?
    public var status: TodoStatus
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var parentID: UUID?

    public init(
        id: UUID,
        title: String,
        project: String?,
        assignee: String?,
        dueDate: String?,
        status: TodoStatus,
        sortOrder: Int,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?,
        parentID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.assignee = assignee
        self.dueDate = dueDate
        self.status = status
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.parentID = parentID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, project, assignee, dueDate, status, sortOrder, createdAt, updatedAt, completedAt, parentID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        status = try container.decode(TodoStatus.self, forKey: .status)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(assignee, forKey: .assignee)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(status, forKey: .status)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(parentID, forKey: .parentID)
    }

    public static func normalizeTitle(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxTitleLength else {
            throw StoreError.invalidTitle
        }
        return trimmed
    }

    public static func normalizeOptional(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func normalizeDueDate(_ raw: String?, calendar: Calendar) throws -> String? {
        guard let raw else { return nil }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let canonical = DueDate.canonical(raw, calendar: calendar) else {
            throw StoreError.invalidDueDate
        }
        return canonical
    }

    public mutating func applyStatus(_ newStatus: TodoStatus, now: Date) {
        if newStatus == .done {
            if status != .done || completedAt == nil {
                completedAt = now
            }
        } else {
            completedAt = nil
        }
        status = newStatus
    }
}

public struct TodoDraft: Sendable {
    public var title: String
    public var project: String?
    public var assignee: String?
    public var dueDate: String?
    public var status: TodoStatus
    public var parentID: UUID?
    public var now: Date

    public init(
        title: String,
        project: String? = nil,
        assignee: String? = nil,
        dueDate: String? = nil,
        status: TodoStatus = .todo,
        parentID: UUID? = nil,
        now: Date = Date()
    ) {
        self.title = title
        self.project = project
        self.assignee = assignee
        self.dueDate = dueDate
        self.status = status
        self.parentID = parentID
        self.now = now
    }
}

/// 编辑器打开时的快照，加上用户最终提交的字段。
/// 只有和快照不同的字段会写到磁盘上的最新任务上，避免旧快照盖掉其他进程刚做的修改。
public struct TodoEdit: Sendable {
    public var base: TodoItem
    public var title: String
    public var project: String?
    public var assignee: String?
    public var dueDate: String?
    public var status: TodoStatus

    public init(
        base: TodoItem,
        title: String,
        project: String?,
        assignee: String?,
        dueDate: String?,
        status: TodoStatus
    ) {
        self.base = base
        self.title = title
        self.project = project
        self.assignee = assignee
        self.dueDate = dueDate
        self.status = status
    }
}
