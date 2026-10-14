import Darwin
import Foundation

public enum StoreError: Error, Equatable, Sendable {
    case containerUnavailable
    case corrupted
    case unsupportedSchema(found: Int, supported: Int)
    case notFound(UUID)
    case invalidTitle
    case invalidDueDate
    case writeFailed
    case backupUnavailable
    case restoreNotNeeded

    public var message: String {
        Copy.storeError(self, AppLanguage.resolved)
    }
}

public struct TodoDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var items: [TodoItem]

    public init(schemaVersion: Int = currentSchemaVersion, items: [TodoItem] = []) {
        self.schemaVersion = schemaVersion
        self.items = items
    }

    public static let empty = TodoDocument()
}

public struct TodoRepository: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func inAppGroup(fileManager: FileManager = .default, bundle: Bundle = .main) throws -> TodoRepository {
        let groupID = AppIdentity.appGroupID(in: bundle)
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw StoreError.containerUnavailable
        }
        let directory = container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("NextUp", isDirectory: true)
        let probe = directory.appendingPathComponent(".access")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: probe, options: .atomic)
            try fileManager.removeItem(at: probe)
        } catch {
            throw StoreError.containerUnavailable
        }
        return TodoRepository(directory: directory)
    }

    public static func localStore(fileManager: FileManager = .default) throws -> TodoRepository {
        let directory = realHomeDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("NextUp", isDirectory: true)
        let probe = directory.appendingPathComponent(".access")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: probe, options: .atomic)
            try fileManager.removeItem(at: probe)
        } catch {
            throw StoreError.containerUnavailable
        }
        return TodoRepository(directory: directory)
    }

    private static func realHomeDirectory() -> URL {
        if let directory = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithFileSystemRepresentation: directory, isDirectory: true, relativeTo: nil)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public var dataFileURL: URL { directory.appendingPathComponent("todos.json") }
    public var backupFileURL: URL { directory.appendingPathComponent("todos.json.bak") }
    public var lockFileURL: URL { directory.appendingPathComponent("todos.lock") }

    public func load() throws -> TodoDocument {
        try prepareDirectory()
        return try withLock(exclusive: false) {
            try readUnlocked()
        }
    }

    public func add(_ draft: TodoDraft, calendar: Calendar = .current) throws -> TodoItem {
        let title = try TodoItem.normalizeTitle(draft.title)
        let project = TodoItem.normalizeOptional(draft.project)
        let assignee = TodoItem.normalizeOptional(draft.assignee)
        let dueDate = try TodoItem.normalizeDueDate(draft.dueDate, calendar: calendar)
        return try mutate { document in
            try appendItem(
                title: title,
                project: project,
                assignee: assignee,
                dueDate: dueDate,
                status: draft.status,
                parentID: draft.parentID,
                now: draft.now,
                calendar: calendar,
                to: &document
            )
        }
    }

    public func apply(_ edit: TodoEdit, now: Date, calendar: Calendar = .current) throws -> TodoItem {
        let title = try TodoItem.normalizeTitle(edit.title)
        let project = TodoItem.normalizeOptional(edit.project)
        let assignee = TodoItem.normalizeOptional(edit.assignee)
        let dueDate = try TodoItem.normalizeDueDate(edit.dueDate, calendar: calendar)
        let baseTitle = try TodoItem.normalizeTitle(edit.base.title)
        let baseProject = TodoItem.normalizeOptional(edit.base.project)
        let baseAssignee = TodoItem.normalizeOptional(edit.base.assignee)
        let baseDueDate = try TodoItem.normalizeDueDate(edit.base.dueDate, calendar: calendar)

        return try mutate { document in
            guard let index = document.items.firstIndex(where: { $0.id == edit.base.id }) else {
                throw StoreError.notFound(edit.base.id)
            }
            var latest = document.items[index]
            if title != baseTitle { latest.title = title }
            if project != baseProject { latest.project = project }
            if assignee != baseAssignee { latest.assignee = assignee }
            if dueDate != baseDueDate { latest.dueDate = dueDate }
            if edit.status != edit.base.status {
                latest.applyStatus(edit.status, now: now)
            }
            if latest != document.items[index] {
                latest.updatedAt = now
            }
            document.items[index] = latest
            return latest
        }
    }

    public func setStatus(id: UUID, status: TodoStatus, now: Date) throws -> TodoItem {
        try mutate { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else {
                throw StoreError.notFound(id)
            }
            if document.items.contains(where: { $0.parentID == id }) {
                return document.items[index]
            }
            var latest = document.items[index]
            latest.applyStatus(status, now: now)
            if latest != document.items[index] {
                latest.updatedAt = now
            }
            document.items[index] = latest
            rollupAncestors(of: latest.parentID, in: &document, now: now)
            return document.items.first { $0.id == id } ?? latest
        }
    }

    private func rollupAncestors(of parentID: UUID?, in document: inout TodoDocument, now: Date) {
        guard let parentID,
              let index = document.items.firstIndex(where: { $0.id == parentID }) else { return }
        let children = document.items.filter { $0.parentID == parentID }
        guard !children.isEmpty else { return }
        var parent = document.items[index]
        if children.allSatisfy({ $0.status == .done }) {
            if parent.status != .done {
                parent.applyStatus(.done, now: now)
                parent.updatedAt = now
                document.items[index] = parent
            }
        } else if parent.status == .done {
            parent.applyStatus(.todo, now: now)
            parent.updatedAt = now
            document.items[index] = parent
        }
        rollupAncestors(of: parent.parentID, in: &document, now: now)
    }

    public func move(id: UUID, before targetID: UUID?) throws {
        try mutate { document in
            guard let moving = document.items.first(where: { $0.id == id }) else {
                throw StoreError.notFound(id)
            }
            if let targetID {
                guard let target = document.items.first(where: { $0.id == targetID }),
                      target.id != id,
                      target.parentID == moving.parentID else {
                    throw StoreError.notFound(targetID)
                }
            }
            var siblings = document.items.filter { $0.parentID == moving.parentID }
            siblings.sort { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            siblings.removeAll { $0.id == id }
            if let targetID, let index = siblings.firstIndex(where: { $0.id == targetID }) {
                siblings.insert(moving, at: index)
            } else {
                siblings.append(moving)
            }
            for (order, sibling) in siblings.enumerated() {
                guard let index = document.items.firstIndex(where: { $0.id == sibling.id }) else { continue }
                document.items[index].sortOrder = order
            }
        }
    }

    public func delete(id: UUID) throws {
        try mutate { document in
            guard document.items.contains(where: { $0.id == id }) else {
                throw StoreError.notFound(id)
            }
            let remove = subtreeIDs(of: id, in: document.items)
            document.items.removeAll { remove.contains($0.id) }
        }
    }

    @discardableResult
    public func delete(ids: Set<UUID>) throws -> [TodoItem] {
        try mutate { document in
            var remove: Set<UUID> = []
            for id in ids where document.items.contains(where: { $0.id == id }) {
                remove.formUnion(subtreeIDs(of: id, in: document.items))
            }
            let removed = document.items.filter { remove.contains($0.id) }
            document.items.removeAll { remove.contains($0.id) }
            return removed
        }
    }

    /// 放回时保留原来的 id、父级和排序。已经存在的跳过；父级已不在的放回顶层。
    public func restore(_ items: [TodoItem]) throws {
        guard !items.isEmpty else { return }
        try mutate { document in
            let existing = Set(document.items.map(\.id))
            let incoming = items.filter { !existing.contains($0.id) }
            let available = existing.union(incoming.map(\.id))
            for var item in incoming {
                if let parentID = item.parentID, !available.contains(parentID) {
                    item.parentID = nil
                }
                document.items.append(item)
            }
        }
    }

    public func addOutline(_ text: String, now: Date = Date(), calendar: Calendar = .current) throws -> [TodoItem] {
        let roots = OutlineParser.parse(text, now: now, calendar: calendar)
        guard !roots.isEmpty else { throw StoreError.invalidTitle }
        return try mutate { document in
            var created: [TodoItem] = []
            func insert(_ entry: OutlineEntry, parentID: UUID?) throws {
                let item = try appendItem(
                    title: entry.title,
                    project: nil,
                    assignee: entry.assignee,
                    dueDate: entry.dueDate,
                    status: .todo,
                    parentID: parentID,
                    now: now,
                    calendar: calendar,
                    to: &document
                )
                created.append(item)
                for child in entry.children {
                    try insert(child, parentID: item.id)
                }
            }
            for root in roots {
                try insert(root, parentID: nil)
            }
            return created
        }
    }

    private func subtreeIDs(of id: UUID, in items: [TodoItem]) -> Set<UUID> {
        var remove: Set<UUID> = [id]
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

    private func resolvedParentID(_ requested: UUID?, in document: TodoDocument) throws -> UUID? {
        guard let requested else { return nil }
        guard document.items.contains(where: { $0.id == requested }) else {
            throw StoreError.notFound(requested)
        }
        var current = requested
        while depth(of: current, in: document) > 1 {
            guard let parentID = document.items.first(where: { $0.id == current })?.parentID else { break }
            current = parentID
        }
        return current
    }

    private func depth(of id: UUID, in document: TodoDocument) -> Int {
        var depth = 0
        var current: UUID? = id
        var steps = 0
        while let id = current, steps < 8 {
            guard let item = document.items.first(where: { $0.id == id }) else { break }
            current = item.parentID
            if current != nil { depth += 1 }
            steps += 1
        }
        return depth
    }

    private func appendItem(
        title: String,
        project: String?,
        assignee: String?,
        dueDate: String?,
        status: TodoStatus,
        parentID: UUID?,
        now: Date,
        calendar: Calendar,
        to document: inout TodoDocument
    ) throws -> TodoItem {
        let parentID = try resolvedParentID(parentID, in: document)
        let nextOrder = (document.items.map(\.sortOrder).max() ?? -1) + 1
        let title = try TodoItem.normalizeTitle(title)
        let project = TodoItem.normalizeOptional(project)
        let assignee = TodoItem.normalizeOptional(assignee)
        let dueDate = try TodoItem.normalizeDueDate(dueDate, calendar: calendar)
        var item = TodoItem(
            id: UUID(),
            title: title,
            project: project,
            assignee: assignee,
            dueDate: dueDate,
            status: .todo,
            sortOrder: nextOrder,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            parentID: parentID
        )
        item.applyStatus(status, now: now)
        document.items.append(item)
        return item
    }

    public func backupIsRestorable() -> Bool {
        (try? prepareDirectory()) != nil && ((try? withLock(exclusive: false) { try readableBackup() }) != nil)
    }

    public func restoreFromBackup() throws -> TodoDocument {
        try prepareDirectory()
        return try withLock(exclusive: true) {
            let backup = try readableBackup()
            if FileManager.default.fileExists(atPath: dataFileURL.path) {
                if (try? readUnlocked()) != nil {
                    throw StoreError.restoreNotNeeded
                }
                try FileManager.default.moveItem(at: dataFileURL, to: damagedFileURL())
            }
            do {
                try FileManager.default.copyItem(at: backupFileURL, to: dataFileURL)
            } catch {
                throw StoreError.writeFailed
            }
            return backup
        }
    }

    private func mutate<T>(_ body: (inout TodoDocument) throws -> T) throws -> T {
        try prepareDirectory()
        return try withLock(exclusive: true) {
            var document = try readUnlocked()
            let original = document
            let result = try body(&document)
            if document != original {
                try writeUnlocked(document)
            }
            return result
        }
    }

    private func prepareDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw StoreError.writeFailed
        }
    }

    private func withLock<T>(exclusive: Bool, _ body: () throws -> T) throws -> T {
        let lock = try FileLock(url: lockFileURL)
        try lock.lock(exclusive: exclusive)
        defer { lock.unlock() }
        return try body()
    }

    private func readUnlocked() throws -> TodoDocument {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
            return .empty
        }
        let data: Data
        do {
            data = try Data(contentsOf: dataFileURL)
        } catch {
            throw StoreError.writeFailed
        }
        return try decode(data)
    }

    private func readableBackup() throws -> TodoDocument {
        guard FileManager.default.fileExists(atPath: backupFileURL.path) else {
            throw StoreError.backupUnavailable
        }
        let data: Data
        do {
            data = try Data(contentsOf: backupFileURL)
        } catch {
            throw StoreError.backupUnavailable
        }
        do {
            return try decode(data)
        } catch StoreError.corrupted {
            throw StoreError.backupUnavailable
        }
    }

    private func decode(_ data: Data) throws -> TodoDocument {
        guard !data.isEmpty else { throw StoreError.corrupted }
        let document: TodoDocument
        do {
            document = try StoreCoding.decoder.decode(TodoDocument.self, from: data)
        } catch {
            throw StoreError.corrupted
        }
        guard document.schemaVersion == TodoDocument.currentSchemaVersion else {
            throw StoreError.unsupportedSchema(found: document.schemaVersion, supported: TodoDocument.currentSchemaVersion)
        }
        return document
    }

    private func writeUnlocked(_ document: TodoDocument) throws {
        let data: Data
        do {
            data = try StoreCoding.encoder.encode(document)
        } catch {
            throw StoreError.writeFailed
        }
        let temporary = directory.appendingPathComponent("todos.json.tmp")
        do {
            try data.write(to: temporary, options: .atomic)
        } catch {
            throw StoreError.writeFailed
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: dataFileURL.path) {
            do {
                if fileManager.fileExists(atPath: backupFileURL.path) {
                    try fileManager.removeItem(at: backupFileURL)
                }
                try fileManager.copyItem(at: dataFileURL, to: backupFileURL)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw StoreError.writeFailed
            }
        }

        do {
            if fileManager.fileExists(atPath: dataFileURL.path) {
                _ = try fileManager.replaceItemAt(dataFileURL, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: dataFileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw StoreError.writeFailed
        }
    }

    private func damagedFileURL() -> URL {
        let base = directory.appendingPathComponent("todos.json.damaged")
        if !FileManager.default.fileExists(atPath: base.path) { return base }
        let stamp = StoreCoding.fileStamp.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("todos.json.damaged-\(stamp)")
    }
}

final class FileLock {
    private let fd: Int32
    private var closed = false

    init(url: URL) throws {
        let fd = open(url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw StoreError.writeFailed }
        self.fd = fd
    }

    func lock(exclusive: Bool) throws {
        try flockRetry(exclusive ? LOCK_EX : LOCK_SH)
    }

    func tryLockExclusive() -> Bool {
        flock(fd, LOCK_EX | LOCK_NB) == 0
    }

    func unlock() {
        guard !closed else { return }
        flock(fd, LOCK_UN)
        close(fd)
        closed = true
    }

    deinit {
        unlock()
    }

    private func flockRetry(_ operation: Int32) throws {
        while true {
            if flock(fd, operation) == 0 { return }
            if errno == EINTR { continue }
            throw StoreError.writeFailed
        }
    }
}

enum StoreCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid date")
            }
            return date
        }
        return decoder
    }()

    static let fileStamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return fractional.string(from: date)
    }

    private static func date(from value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: value) ?? plain.date(from: value)
    }

    private static let lock = NSLock()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
