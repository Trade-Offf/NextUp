import XCTest
@testable import NextUpShared

final class TodoRepositoryTests: XCTestCase {
    private var directory: URL!
    private var repository: TodoRepository!
    private let calendar = StoreFixtures.gregorian("Asia/Shanghai")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NextUp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = TodoRepository(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testChildStaysOneLevelAndLeavesWithItsParent() throws {
        let parent = try repository.add(TodoDraft(title: "父任务"), calendar: calendar)
        let child = try repository.add(TodoDraft(title: "子任务", parentID: parent.id), calendar: calendar)
        let folded = try repository.add(TodoDraft(title: "再下一层", parentID: child.id), calendar: calendar)
        let stored = try repository.load().items
        XCTAssertEqual(stored.first { $0.id == child.id }?.parentID, parent.id)
        XCTAssertEqual(stored.first { $0.id == folded.id }?.parentID, child.id)
        let capped = try repository.add(TodoDraft(title: "第四层", parentID: folded.id), calendar: calendar)
        XCTAssertEqual(try repository.load().items.first { $0.id == capped.id }?.parentID, child.id)
        try repository.delete(id: parent.id)
        XCTAssertTrue(try repository.load().items.isEmpty)
    }

    func testBulkDeleteTakesChildrenAndRestorePutsThemBack() throws {
        let parent = try repository.add(TodoDraft(title: "父任务"), calendar: calendar)
        let child = try repository.add(TodoDraft(title: "子任务", parentID: parent.id), calendar: calendar)
        let other = try repository.add(TodoDraft(title: "另一条"), calendar: calendar)
        let keep = try repository.add(TodoDraft(title: "留着"), calendar: calendar)
        let before = try repository.load().items

        let removed = try repository.delete(ids: [parent.id, other.id])
        XCTAssertEqual(Set(removed.map(\.id)), [parent.id, child.id, other.id])
        XCTAssertEqual(try repository.load().items.map(\.id), [keep.id])

        try repository.restore(removed)
        let after = try repository.load().items
        XCTAssertEqual(after.sorted { $0.id.uuidString < $1.id.uuidString }, before.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(after.first { $0.id == child.id }?.parentID, parent.id)

        try repository.restore(removed)
        XCTAssertEqual(try repository.load().items.count, before.count)
    }

    func testRestoreKeepsAChangeMadeInBetween() throws {
        let first = try repository.add(TodoDraft(title: "甲"), calendar: calendar)
        let second = try repository.add(TodoDraft(title: "乙"), calendar: calendar)
        let removed = try repository.delete(ids: [first.id])
        _ = try repository.setStatus(id: second.id, status: .done, now: Date(timeIntervalSince1970: 1_762_000_000))

        try repository.restore(removed)
        XCTAssertEqual(try status(of: first.id), .todo)
        XCTAssertEqual(try status(of: second.id), .done)
    }

    func testRestoreLiftsAnOrphanToTheTop() throws {
        let parent = try repository.add(TodoDraft(title: "父任务"), calendar: calendar)
        let child = try repository.add(TodoDraft(title: "子任务", parentID: parent.id), calendar: calendar)
        let removedChild = try repository.delete(ids: [child.id])
        try repository.delete(id: parent.id)

        try repository.restore(removedChild)
        XCTAssertNil(try repository.load().items.first { $0.id == child.id }?.parentID)
    }

    func testFiveHundredItemsDeleteAndRestoreStayWithinAFewSeconds() throws {
        let outline = (1...500).map { "\($0). 任务 \($0)" }.joined(separator: "\n")
        let now = Date(timeIntervalSince1970: 1_762_000_000)
        let created = try repository.addOutline(outline, now: now, calendar: calendar)
        XCTAssertEqual(created.count, 500)
        let started = Date()
        let removed = try repository.delete(ids: Set(created.map(\.id)))
        XCTAssertEqual(removed.count, 500)
        XCTAssertTrue(try repository.load().items.isEmpty)
        try repository.restore(removed)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        let restored = try repository.load().items.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(restored.map(\.title), created.sorted { $0.sortOrder < $1.sortOrder }.map(\.title))
        XCTAssertEqual(restored.map(\.id), created.sorted { $0.sortOrder < $1.sortOrder }.map(\.id))
    }

    func testUndoingAPastedOutlineLeavesTheStoreAsItWas() throws {
        let existing = try repository.add(TodoDraft(title: "原有"), calendar: calendar)
        let outline = (1...300).map { "\($0). 粘错的第 \($0) 行" }.joined(separator: "\n")
        let created = try repository.addOutline(outline, now: Date(timeIntervalSince1970: 1_762_000_000), calendar: calendar)
        XCTAssertEqual(created.count, 300)

        try repository.delete(ids: Set(created.map(\.id)))
        XCTAssertEqual(try repository.load().items.map(\.id), [existing.id])
    }

    func testParentCompletesOnlyWhenEveryChildIsDone() throws {
        let parent = try repository.add(TodoDraft(title: "父任务"), calendar: calendar)
        let first = try repository.add(TodoDraft(title: "甲", parentID: parent.id), calendar: calendar)
        let second = try repository.add(TodoDraft(title: "乙", parentID: parent.id), calendar: calendar)
        let now = Date(timeIntervalSince1970: 1_762_000_000)

        _ = try repository.setStatus(id: parent.id, status: .done, now: now)
        XCTAssertEqual(try status(of: parent.id), .todo)

        _ = try repository.setStatus(id: first.id, status: .done, now: now)
        XCTAssertEqual(try status(of: parent.id), .todo)
        XCTAssertEqual(try status(of: first.id), .done)

        _ = try repository.setStatus(id: second.id, status: .done, now: now)
        XCTAssertEqual(try status(of: parent.id), .done)

        _ = try repository.setStatus(id: second.id, status: .todo, now: now)
        XCTAssertEqual(try status(of: parent.id), .todo)
        XCTAssertEqual(try status(of: second.id), .todo)
    }

    func testMoveReordersSiblingsAndKeepsTheParent() throws {
        let parent = try repository.add(TodoDraft(title: "父任务"), calendar: calendar)
        let first = try repository.add(TodoDraft(title: "甲", parentID: parent.id), calendar: calendar)
        _ = try repository.add(TodoDraft(title: "乙", parentID: parent.id), calendar: calendar)
        let third = try repository.add(TodoDraft(title: "丙", parentID: parent.id), calendar: calendar)

        try repository.move(id: third.id, before: first.id)
        XCTAssertEqual(try siblingTitles(of: parent.id), ["丙", "甲", "乙"])

        try repository.move(id: first.id, before: nil)
        XCTAssertEqual(try siblingTitles(of: parent.id), ["丙", "乙", "甲"])
    }

    private func status(of id: UUID) throws -> TodoStatus? {
        try repository.load().items.first { $0.id == id }?.status
    }

    private func siblingTitles(of parentID: UUID) throws -> [String] {
        try repository.load().items
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
            .map(\.title)
    }

    func testMissingFileIsAnEmptyStore() throws {
        let document = try repository.load()
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertTrue(document.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.dataFileURL.path))
    }

    func testAddPersistsFieldsAndKeepsInternalNewlines() throws {
        let now = Date(timeIntervalSince1970: 1_762_000_000)
        let item = try repository.add(
            TodoDraft(title: "  与 Allen 对齐\n排期  ", project: " BD ", assignee: " ", dueDate: "2026-10-14", now: now),
            calendar: calendar
        )
        let reloaded = TodoRepository(directory: directory)
        let stored = try reloaded.load().items
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].id, item.id)
        XCTAssertEqual(stored[0].title, "与 Allen 对齐\n排期")
        XCTAssertEqual(stored[0].project, "BD")
        XCTAssertNil(stored[0].assignee)
        XCTAssertEqual(stored[0].dueDate, "2026-10-14")
        XCTAssertEqual(stored[0].status, .todo)
        XCTAssertNil(stored[0].completedAt)
        XCTAssertEqual(stored[0].createdAt.timeIntervalSince(now), 0, accuracy: 0.001)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("todos.json.tmp").path))
    }

    func testInvalidTitleDoesNotCreateAFile() throws {
        XCTAssertThrowsError(try repository.add(TodoDraft(title: "   "))) { error in
            XCTAssertEqual(error as? StoreError, .invalidTitle)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.dataFileURL.path))
    }

    func testSecondWriteKeepsThePreviousFileAsBackup() throws {
        _ = try repository.add(TodoDraft(title: "第一件"))
        _ = try repository.add(TodoDraft(title: "第二件"))
        let backup = try Data(contentsOf: repository.backupFileURL)
        let document = try StoreCoding.decoder.decode(TodoDocument.self, from: backup)
        XCTAssertEqual(document.items.map(\.title), ["第一件"])
    }

    func testEditAppliesOnlyChangedFieldsOntoTheLatestItem() throws {
        let original = try repository.add(TodoDraft(title: "原标题", project: "旧项目", dueDate: "2026-10-20"), calendar: calendar)
        let now = Date(timeIntervalSince1970: 1_762_000_100)
        _ = try repository.setStatus(id: original.id, status: .waiting, now: now)

        let edited = try repository.apply(
            TodoEdit(base: original, title: "新标题", project: "旧项目", assignee: nil, dueDate: "2026-10-20", dueTime: original.dueTime, status: .todo),
            now: Date(timeIntervalSince1970: 1_762_000_200),
            calendar: calendar
        )
        XCTAssertEqual(edited.title, "新标题")
        XCTAssertEqual(edited.project, "旧项目")
        XCTAssertEqual(edited.status, .waiting)
        XCTAssertNil(edited.completedAt)
    }

    func testCompletingOneItemDoesNotTouchAnother() throws {
        let first = try repository.add(TodoDraft(title: "甲"))
        let second = try repository.add(TodoDraft(title: "乙"))
        let doneAt = Date(timeIntervalSince1970: 1_762_000_300)
        _ = try repository.setStatus(id: first.id, status: .done, now: doneAt)

        let items = try repository.load().items
        XCTAssertEqual(items.first { $0.id == first.id }?.status, .done)
        XCTAssertEqual(items.first { $0.id == first.id }?.completedAt?.timeIntervalSince(doneAt) ?? 99, 0, accuracy: 0.001)
        XCTAssertEqual(items.first { $0.id == second.id }?.status, .todo)
        XCTAssertNil(items.first { $0.id == second.id }?.completedAt)
    }

    func testDeletedItemDoesNotCrashALaterStatusChange() {
        let item = try? repository.add(TodoDraft(title: "会删除"))
        XCTAssertNotNil(item)
        XCTAssertNoThrow(try repository.delete(id: item!.id))
        XCTAssertThrowsError(try repository.setStatus(id: item!.id, status: .done, now: Date())) { error in
            XCTAssertEqual(error as? StoreError, .notFound(item!.id))
        }
    }

    func testCorruptFileIsPreservedAndNotTreatedAsEmpty() throws {
        _ = try repository.add(TodoDraft(title: "还在"))
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: repository.dataFileURL)
        let before = try Data(contentsOf: repository.dataFileURL)

        XCTAssertThrowsError(try repository.load()) { error in
            XCTAssertEqual(error as? StoreError, .corrupted)
        }
        XCTAssertThrowsError(try repository.add(TodoDraft(title: "不该写入"))) { error in
            XCTAssertEqual(error as? StoreError, .corrupted)
        }
        XCTAssertEqual(try Data(contentsOf: repository.dataFileURL), before)
    }

    func testUnsupportedSchemaIsNotRewritten() throws {
        let payload = #"{"schemaVersion":99,"items":[]}"#.data(using: .utf8)!
        try payload.write(to: repository.dataFileURL)
        XCTAssertThrowsError(try repository.load()) { error in
            XCTAssertEqual(error as? StoreError, .unsupportedSchema(found: 99, supported: 1))
        }
        XCTAssertThrowsError(try repository.add(TodoDraft(title: "不该写入")))
        XCTAssertEqual(try Data(contentsOf: repository.dataFileURL), payload)
    }

    func testRestoreMovesCorruptFileAsideAndUsesBackup() throws {
        _ = try repository.add(TodoDraft(title: "备份里的任务"))
        _ = try repository.add(TodoDraft(title: "后来的任务"))
        try Data("broken".utf8).write(to: repository.dataFileURL)

        let restored = try repository.restoreFromBackup()
        XCTAssertEqual(restored.items.map(\.title), ["备份里的任务"])
        XCTAssertEqual(try repository.load().items.map(\.title), ["备份里的任务"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("todos.json.damaged").path))
        XCTAssertThrowsError(try repository.restoreFromBackup()) { error in
            XCTAssertEqual(error as? StoreError, .restoreNotNeeded)
        }
    }

    func testParallelAddsAndStatusChangesAllSurvive() throws {
        let count = 24
        DispatchQueue.concurrentPerform(iterations: count) { index in
            _ = try? repository.add(TodoDraft(title: "并发\(index)", now: Date(timeIntervalSince1970: TimeInterval(1_762_100_000 + index))))
        }
        let items = try repository.load().items
        XCTAssertEqual(Set(items.map(\.title)).count, count)

        let targets = Array(items.prefix(2))
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let status: TodoStatus = index == 0 ? .done : .waiting
            _ = try? repository.setStatus(id: targets[index].id, status: status, now: Date())
        }
        let reloaded = try repository.load().items
        XCTAssertEqual(reloaded.first { $0.id == targets[0].id }?.status, .done)
        XCTAssertEqual(reloaded.first { $0.id == targets[1].id }?.status, .waiting)
        XCTAssertEqual(reloaded.count, count)
    }

    func testCrossProcessLockWaitsForTheOtherProcess() throws {
        let holder = try LockHolder.make()
        let process = try holder.hold(lockFile: repository.lockFileURL, seconds: 0.8)
        defer { process.terminate() }

        XCTAssertTrue(waitUntilLockIsHeld())
        let started = Date()
        let item = try repository.add(TodoDraft(title: "锁释放后写入"))
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 0.3)
        process.waitUntilExit()
        XCTAssertEqual(try repository.load().items.map(\.id), [item.id])
    }

    private func waitUntilLockIsHeld() -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let probe = try? FileLock(url: repository.lockFileURL), probe.tryLockExclusive() == false {
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }
}

private struct LockHolder {
    let executable: URL

    static func make() throws -> LockHolder {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("nextup-lock-\(UUID().uuidString).c")
        let binary = source.deletingPathExtension()
        let program = """
        #include <fcntl.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <unistd.h>
        #include <sys/file.h>
        int main(int argc, char **argv) {
            if (argc < 3) return 1;
            int fd = open(argv[1], O_RDWR | O_CREAT, 0644);
            if (fd < 0) return 2;
            if (flock(fd, LOCK_EX) != 0) return 3;
            usleep((useconds_t)(atof(argv[2]) * 1000000.0));
            flock(fd, LOCK_UN);
            close(fd);
            return 0;
        }
        """
        try program.write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-O2", source.path, "-o", binary.path]
        try compiler.run()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else {
            throw StoreError.writeFailed
        }
        return LockHolder(executable: binary)
    }

    func hold(lockFile: URL, seconds: Double) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = [lockFile.path, String(seconds)]
        try process.run()
        return process
    }
}
