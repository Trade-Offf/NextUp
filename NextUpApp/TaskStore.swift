import Foundation
import NextUpShared
import WidgetKit

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var document = TodoDocument.empty
    @Published private(set) var loadError: StoreError?
    @Published var notice: String?
    @Published var highlightedID: UUID?
    @Published private(set) var settlingIDs: Set<UUID> = []
    @Published private(set) var language = AppLanguage.resolved
    private var repository: TodoRepository?
    private var settleTask: Task<Void, Never>?

    func reload() {
        do {
            let repository = try currentRepository()
            document = try repository.load()
            loadError = nil
        } catch let error as StoreError {
            document = .empty
            loadError = error
        } catch {
            document = .empty
            loadError = .writeFailed
        }
        reloadWidget()
    }

    func add(title: String, project: String? = nil, assignee: String? = nil, dueDate: String? = nil, status: TodoStatus = .todo, parentID: UUID? = nil) throws {
        let repository = try currentRepository()
        _ = try repository.add(TodoDraft(title: title, project: project, assignee: assignee, dueDate: dueDate, status: status, parentID: parentID))
        reload()
    }

    func addOutline(_ text: String) throws {
        let repository = try currentRepository()
        _ = try repository.addOutline(text, now: Date(), calendar: .current)
        reload()
    }

    func setStatus(id: UUID, status: TodoStatus) {
        let previous = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0.status) })
        do {
            let repository = try currentRepository()
            _ = try repository.setStatus(id: id, status: status, now: Date())
            reload()
            noteParentsThatJustFinished(previous: previous, editedID: id)
        } catch let error as StoreError {
            if case .notFound = error {
                notice = error.message
                reload()
            } else {
                loadError = error
            }
        } catch {
            loadError = .writeFailed
        }
    }

    @discardableResult
    func rename(id: UUID, title: String) -> Bool {
        guard let item = document.items.first(where: { $0.id == id }) else { return false }
        do {
            let repository = try currentRepository()
            let edit = TodoEdit(
                base: item,
                title: title,
                project: item.project,
                assignee: item.assignee,
                dueDate: item.dueDate,
                status: item.status
            )
            _ = try repository.apply(edit, now: Date())
            reload()
            return true
        } catch let error as StoreError {
            notice = error.message
            return false
        } catch {
            loadError = .writeFailed
            return false
        }
    }

    func move(id: UUID, before targetID: UUID?) {
        do {
            let repository = try currentRepository()
            try repository.move(id: id, before: targetID)
            reload()
        } catch let error as StoreError {
            if case .notFound = error {
                notice = error.message
                reload()
            } else {
                loadError = error
            }
        } catch {
            loadError = .writeFailed
        }
    }

    func delete(id: UUID) {
        do {
            let repository = try currentRepository()
            try repository.delete(id: id)
            reload()
        } catch let error as StoreError {
            if case .notFound = error {
                notice = error.message
                reload()
            } else {
                loadError = error
            }
        } catch {
            loadError = .writeFailed
        }
    }

    func restoreBackup() {
        do {
            let repository = try currentRepository()
            _ = try repository.restoreFromBackup()
            reload()
            notice = Copy.text(.restored, language)
        } catch let error as StoreError {
            loadError = error
        } catch {
            loadError = .writeFailed
        }
    }

    func backupIsRestorable() -> Bool {
        repository?.backupIsRestorable() ?? false
    }

    func open(url: URL) {
        guard url.scheme == AppIdentity.urlScheme() else { return }
        reload()
        guard url.host == "task" else { return }
        let rawID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let id = UUID(uuidString: rawID) else {
            notice = Copy.text(.unrecognizedLink, language)
            return
        }
        if document.items.contains(where: { $0.id == id }) {
            notice = nil
            highlightedID = id
        } else {
            highlightedID = nil
            notice = Copy.text(.missingTask, language)
        }
    }

    private func noteParentsThatJustFinished(previous: [UUID: TodoStatus], editedID: UUID) {
        let flipped = document.items.compactMap { item -> UUID? in
            guard item.id != editedID else { return nil }
            guard previous[item.id] != .done, item.status == .done else { return nil }
            guard document.items.contains(where: { $0.parentID == item.id }) else { return nil }
            return item.id
        }
        guard !flipped.isEmpty else { return }
        settlingIDs.formUnion(flipped)
        settleTask?.cancel()
        let held = settlingIDs
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            settlingIDs.subtract(held)
        }
    }

    private func currentRepository() throws -> TodoRepository {
        if let repository { return repository }
        // 有 Apple ID 和 App Group 后再改回：
        // let repository = try TodoRepository.inAppGroup()
        let repository = try TodoRepository.localStore()
        self.repository = repository
        return repository
    }

    func selectLanguage(_ language: AppLanguage) {
        do {
            try AppPreferences.save(language)
            self.language = language
            reloadWidget()
        } catch let error as StoreError {
            notice = error.message
        } catch {
            notice = StoreError.writeFailed.message
        }
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: AppIdentity.widgetKind())
    }
}
