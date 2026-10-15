import AppKit
import Foundation
import NextUpShared

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var document = TodoDocument.empty
    @Published private(set) var loadError: StoreError?
    @Published var notice: String?
    @Published var highlightedID: UUID?
    @Published private(set) var settlingIDs: Set<UUID> = []
    @Published private(set) var language = AppLanguage.resolved
    @Published private(set) var showsWidgetBadge = AppPreferences.showsWidgetBadge()
    @Published private(set) var shortcuts = AppPreferences.shortcutMap()
    @Published private(set) var isRecordingShortcut = false
    @Published private(set) var recordingCommand: AppCommand?
    @Published private(set) var recordingNote: ShortcutRecordingNote?
    @Published private(set) var shortcutError: String?
    @Published private(set) var selection: Set<UUID> = []
    @Published var showsCompleted = false
    /// 大批删除时不做行动画。撤销放回仍用原来的 settle。
    @Published private(set) var animatesListChanges = true
    @Published private(set) var fadesRowRemoval = false
    @Published private(set) var focusComposerToken = 0
    @Published var renameRequest: UUID?
    @Published private(set) var selectionScrollID: UUID?
    @Published private(set) var isTyping = false
    @Published private(set) var windowIsKey = false
    /// 窗口自己的撤销栈，只给输入框用。任务的回退另放在 modelUndo，避免 ⌘Z 先把刚提交的文字填回去。
    weak var undoManager: UndoManager?
    private let modelUndo: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()
    @Published private(set) var undoRevision = 0
    private var undoObservers: [NSObjectProtocol] = []
    private var undoKeyMonitor: Any?
    private var fieldsOwningUndo: Set<String> = []
    weak var mainWindow: NSWindow?
    private var repository: TodoRepository?
    private var settleTask: Task<Void, Never>?
    private var selectionAnchor: UUID?
    private var typingTokens: Set<String> = []

    func reload() {
        reload(animating: true, fadeRemoval: false)
    }

    func add(title: String, project: String? = nil, assignee: String? = nil, dueDate: String? = nil, status: TodoStatus = .todo, parentID: UUID? = nil) throws {
        let repository = try currentRepository()
        let item = try repository.add(TodoDraft(title: title, project: project, assignee: assignee, dueDate: dueDate, status: status, parentID: parentID))
        reload()
        registerCreation([item], name: Copy.text(.undoAdd, language))
    }

    func addOutline(_ text: String) throws {
        let repository = try currentRepository()
        let created = try repository.addOutline(text, now: Date(), calendar: .current)
        reload()
        registerCreation(created, name: Copy.undoPaste(created.count, language))
    }

    func setStatus(id: UUID, status: TodoStatus) {
        let previous = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0.status) })
        do {
            _ = try currentRepository().setStatus(id: id, status: status, now: Date())
            reload()
            noteParentsThatJustFinished(previous: previous, editedID: id)
            if let before = previous[id], before != status {
                let name = Copy.text(status == .done ? .undoComplete : .undoReopen, language)
                register(name) { $0.apply(statuses: [id: before], name: name) }
            }
        } catch {
            fail(error)
        }
    }

    func toggleSelectedCompletion() {
        let targets = document.items.filter { item in
            selection.contains(item.id) && !hasChildren(item.id)
        }
        guard !targets.isEmpty else { return }
        let restoring = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.status) })
        let previous = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0.status) })
        do {
            let repository = try currentRepository()
            let now = Date()
            for item in targets {
                let next: TodoStatus = item.status == .done ? .todo : .done
                _ = try repository.setStatus(id: item.id, status: next, now: now)
            }
            reload()
            for item in targets {
                noteParentsThatJustFinished(previous: previous, editedID: item.id)
            }
            let name = Copy.text(targets.contains { $0.status != .done } ? .undoComplete : .undoReopen, language)
            register(name) { $0.apply(statuses: restoring, name: name) }
        } catch {
            fail(error)
        }
    }

    @discardableResult
    func rename(id: UUID, title: String) -> Bool {
        guard let item = document.items.first(where: { $0.id == id }) else { return false }
        let old = item.title
        guard writeTitle(id: id, title: title) else { return false }
        if let latest = document.items.first(where: { $0.id == id }), latest.title != old {
            let name = Copy.text(.undoRename, language)
            let written = latest.title
            register(name) { $0.revertTitle(id: id, to: old, then: written, name: name) }
        }
        return true
    }

    func setDeadline(id: UUID, dueDate: String?, dueTime: String?) {
        guard let item = document.items.first(where: { $0.id == id }) else { return }
        let previousDate = item.dueDate
        let previousTime = item.dueTime
        guard writeDeadline(id: id, dueDate: dueDate, dueTime: dueTime) else { return }
        guard let latest = document.items.first(where: { $0.id == id }) else { return }
        guard latest.dueDate != previousDate || latest.dueTime != previousTime else { return }
        let name = Copy.text(.undoDeadline, language)
        let writtenDate = latest.dueDate
        let writtenTime = latest.dueTime
        register(name) {
            $0.revertDeadline(
                id: id,
                dueDate: previousDate,
                dueTime: previousTime,
                thenDate: writtenDate,
                thenTime: writtenTime,
                name: name
            )
        }
    }

    func move(id: UUID, before targetID: UUID?) {
        let previous = nextSibling(after: id)
        performMove(id: id, before: targetID, undoBefore: previous, name: Copy.text(.undoMove, language))
    }

    func nudgeSelection(upward: Bool) {
        guard selection.count == 1, let id = selection.first else { return }
        guard let moving = document.items.first(where: { $0.id == id }) else { return }
        let siblings = orderedSiblings(of: moving.parentID)
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return }
        if upward {
            guard index > 0 else { return }
            move(id: id, before: siblings[index - 1].id)
        } else {
            guard index + 1 < siblings.count else { return }
            let before = index + 2 < siblings.count ? siblings[index + 2].id : nil
            move(id: id, before: before)
        }
    }

    func delete(ids: Set<UUID>, actionName: String? = nil) {
        guard !ids.isEmpty else { return }
        do {
            let repository = try currentRepository()
            let removed = try repository.delete(ids: ids)
            reload(animating: removed.count <= 50, fadeRemoval: removed.count > 1)
            guard !removed.isEmpty else { return }
            let name = actionName ?? Copy.undoDelete(removed.count, language)
            registerRemoval(removed, name: name)
        } catch {
            fail(error)
        }
    }

    func deleteSelection() {
        delete(ids: selection)
    }

    func clearCompleted() {
        let ids = Set(document.items.filter { $0.status == .done }.map(\.id))
        delete(ids: ids, actionName: Copy.text(.clearCompleted, language))
    }

    func clearCount(_ scope: TodoClearing.Scope) -> Int {
        TodoClearing.removalIDs(in: document.items, scope: scope, now: Date(), calendar: .current).count
    }

    func clear(_ scope: TodoClearing.Scope) {
        let name = Copy.text(scope == .writtenToday ? .clearToday : .clearHistory, language)
        delete(ids: TodoClearing.removalIDs(in: document.items, scope: scope, now: Date(), calendar: .current), actionName: name)
    }

    var hasCompleted: Bool {
        document.items.contains { $0.status == .done }
    }

    var hasOpen: Bool {
        document.items.contains { $0.status != .done }
    }

    var handlesListKeys: Bool { windowIsKey && !isTyping }

    var selectionIsToggleable: Bool {
        document.items.contains { selection.contains($0.id) && !hasChildren($0.id) }
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

    func selectOnly(_ id: UUID) {
        selection = [id]
        selectionAnchor = id
    }

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
            if selectionAnchor == id { selectionAnchor = selection.first }
        } else {
            selection.insert(id)
            selectionAnchor = id
        }
    }

    func selectRange(to id: UUID) {
        let order = visibleOrder()
        let anchor = selectionAnchor ?? selection.first ?? id
        guard let start = order.firstIndex(of: anchor), let end = order.firstIndex(of: id) else {
            selectOnly(id)
            return
        }
        let lower = min(start, end)
        let upper = max(start, end)
        selection = Set(order[lower...upper])
        selectionAnchor = anchor
    }

    func selectAllOpen() {
        let open = document.items.filter { $0.status != .done }.map(\.id)
        selection = Set(open)
        selectionAnchor = visibleOrder().first { selection.contains($0) } ?? open.first
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    func moveSelection(by delta: Int) {
        let order = visibleOrder()
        guard !order.isEmpty else { return }
        if selection.isEmpty {
            selectOnly(delta >= 0 ? order[0] : order[order.count - 1])
            selectionScrollID = selection.first
            return
        }
        let origin = delta >= 0
            ? order.last { selection.contains($0) }
            : order.first { selection.contains($0) }
        guard let origin, let index = order.firstIndex(of: origin) else {
            selectOnly(order[0])
            selectionScrollID = order[0]
            return
        }
        let next = index + delta
        guard order.indices.contains(next) else { return }
        selectOnly(order[next])
        selectionScrollID = order[next]
    }

    func requestNewTask() {
        mainWindow?.makeKeyAndOrderFront(nil)
        focusComposerToken += 1
    }

    func requestRename() {
        guard selection.count == 1 else { return }
        renameRequest = selection.first
    }

    func consumeRenameRequest() {
        renameRequest = nil
    }

    func setTyping(_ token: String, active: Bool) {
        if active { typingTokens.insert(token) } else { typingTokens.remove(token) }
        let editing = !typingTokens.isEmpty
        if editing != isTyping { isTyping = editing }
    }

    @Published private(set) var textFieldOwnsUndo = false

    func setFieldOwnsUndo(_ token: String, active: Bool) {
        if active { fieldsOwningUndo.insert(token) } else { fieldsOwningUndo.remove(token) }
        let owns = !fieldsOwningUndo.isEmpty
        if textFieldOwnsUndo != owns { textFieldOwnsUndo = owns }
    }

    /// 主窗口输入框获得焦点时由界面换上。回车直接提交，不往多行里再插一行。
    var composerReturn: (() -> Void)?

    func setWindow(_ window: NSWindow?, isKey: Bool) {
        mainWindow = window
        if windowIsKey != isKey { windowIsKey = isKey }
    }

    func visibleOrder() -> [UUID] {
        let roots = orderedSiblings(of: nil)
        let open = roots.filter { $0.status != .done || settlingIDs.contains($0.id) }
        let done = roots.filter { $0.status == .done && !settlingIDs.contains($0.id) }
        var order = open.flatMap(branch)
        if showsCompleted { order += done.flatMap(branch) }
        return order
    }

    func hasChildren(_ id: UUID) -> Bool {
        document.items.contains { $0.parentID == id }
    }

    var undoMenuTitle: String {
        _ = undoRevision
        let action = modelUndo.canUndo ? modelUndo.undoActionName : ""
        return Copy.rollbackTitle(action, language)
    }

    var redoMenuTitle: String {
        _ = undoRevision
        let action = modelUndo.canRedo ? modelUndo.redoActionName : ""
        return Copy.redoTitle(action, language)
    }

    var canUndo: Bool {
        _ = undoRevision
        return modelUndo.canUndo
    }
    var canRedo: Bool {
        _ = undoRevision
        return modelUndo.canRedo
    }
    var isApplyingUndo: Bool {
        modelUndo.isUndoing || modelUndo.isRedoing
            || undoManager?.isUndoing == true
            || undoManager?.isRedoing == true
    }

    func undo() {
        guard modelUndo.canUndo else { return }
        modelUndo.undo()
    }

    func redo() {
        guard modelUndo.canRedo else { return }
        modelUndo.redo()
    }

    func observeUndoStack() {
        guard undoObservers.isEmpty else { return }
        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup,
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange
        ]
        for name in names {
            undoObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let manager = note.object as? UndoManager, manager !== self.modelUndo { return }
                    self.undoRevision += 1
                }
            })
        }
        undoKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.routeKey(event) }
        }
    }

    func beginRecording(_ command: AppCommand) {
        recordingCommand = command
        recordingNote = nil
        shortcutError = nil
        isRecordingShortcut = true
    }

    func cancelRecording() {
        recordingCommand = nil
        recordingNote = nil
        isRecordingShortcut = false
    }

    func confirmReplacement() {
        guard case .conflict(let other, let binding) = recordingNote, let command = recordingCommand else { return }
        var map = shortcuts
        map.replace(binding, to: command, from: other)
        if persist(map) { cancelRecording() }
    }

    func resetShortcuts() {
        var map = shortcuts
        map.reset()
        persist(map)
        cancelRecording()
    }

    func menuBinding(for command: AppCommand, enabled: Bool) -> ShortcutBinding? {
        guard enabled, let binding = shortcuts.binding(for: command) else { return nil }
        if isTyping && !binding.worksWhileTyping { return nil }
        if textFieldOwnsUndo && (command == .undo || command == .redo) { return nil }
        return binding
    }

    func commandEnabled(_ command: AppCommand, when ready: Bool) -> Bool {
        guard ready else { return false }
        if command == .newTask { return true }
        guard windowIsKey else { return false }
        if !isTyping { return true }
        return shortcuts.binding(for: command)?.worksWhileTyping == true
    }

    private func routeKey(_ event: NSEvent) -> NSEvent? {
        if isRecordingShortcut {
            handleRecordedKey(event)
            return nil
        }
        if windowIsKey, isPlainReturn(event), let composerReturn {
            composerReturn()
            return nil
        }
        guard let binding = ShortcutBinding(event: event) else { return event }
        guard let command = command(matching: binding) else { return event }
        if command == .undo || command == .redo {
            return routeUndo(binding, redo: command == .redo, event: event)
        }
        guard shortcutIsActive(command, binding: binding), perform(command) else { return event }
        return nil
    }

    private func command(matching binding: ShortcutBinding) -> AppCommand? {
        AppCommand.allCases.first { shortcuts.binding(for: $0) == binding }
    }

    private func routeUndo(_ binding: ShortcutBinding, redo: Bool, event: NSEvent) -> NSEvent? {
        if isTyping && !binding.worksWhileTyping {
            return event
        }
        if focusedFieldHasText() {
            let selector = redo ? Selector(("redo:")) : Selector(("undo:"))
            NSApp.sendAction(selector, to: nil, from: nil)
            return nil
        }
        guard windowIsKey else { return event }
        if redo { self.redo() } else { undo() }
        return nil
    }

    private func shortcutIsActive(_ command: AppCommand, binding: ShortcutBinding) -> Bool {
        if command == .newTask {
            return !isTyping || binding.worksWhileTyping
        }
        guard windowIsKey else { return false }
        if isTyping && !binding.worksWhileTyping { return false }
        return true
    }

    private func perform(_ command: AppCommand) -> Bool {
        switch command {
        case .newTask:
            requestNewTask()
            return true
        case .selectPrevious:
            guard !visibleOrder().isEmpty else { return false }
            moveSelection(by: -1)
            return true
        case .selectNext:
            guard !visibleOrder().isEmpty else { return false }
            moveSelection(by: 1)
            return true
        case .selectAllTasks:
            guard hasOpen else { return false }
            selectAllOpen()
            return true
        case .clearSelection:
            guard !selection.isEmpty else { return false }
            clearSelection()
            return true
        case .toggleDone:
            guard selectionIsToggleable else { return false }
            toggleSelectedCompletion()
            return true
        case .rename:
            guard selection.count == 1 else { return false }
            requestRename()
            return true
        case .moveUp:
            guard selection.count == 1 else { return false }
            nudgeSelection(upward: true)
            return true
        case .moveDown:
            guard selection.count == 1 else { return false }
            nudgeSelection(upward: false)
            return true
        case .deleteSelection:
            guard !selection.isEmpty else { return false }
            deleteSelection()
            return true
        case .clearCompleted:
            guard hasCompleted else { return false }
            clearCompleted()
            return true
        case .undo, .redo:
            return false
        }
    }

    private func handleRecordedKey(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
        if event.keyCode == 53, flags.isEmpty {
            cancelRecording()
            return
        }
        if event.keyCode == 51, flags.isEmpty {
            if let command = recordingCommand {
                var map = shortcuts
                map.clear(command)
                if !persist(map) { return }
            }
            cancelRecording()
            return
        }
        guard let binding = ShortcutBinding(event: event), let command = recordingCommand else { return }
        switch shortcuts.check(binding, for: command) {
        case .reserved:
            recordingNote = .reserved
        case .conflict(let other):
            recordingNote = .conflict(other, binding)
        case .available:
            var map = shortcuts
            map.assign(binding, to: command)
            if persist(map) { cancelRecording() }
        }
    }

    @discardableResult
    private func persist(_ map: ShortcutMap) -> Bool {
        do {
            try AppPreferences.save(map)
            shortcuts = map
            shortcutError = nil
            return true
        } catch let error as StoreError {
            shortcutError = error.message
            return false
        } catch {
            shortcutError = StoreError.writeFailed.message
            return false
        }
    }

    private func focusedFieldHasText() -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return !textView.string.isEmpty
    }

    private func isPlainReturn(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }
        return event.keyCode == 36 || event.keyCode == 76
    }

    /// 输入框清掉已提交的文字时，不要把这次清空记成撤销。否则 ⌘Z 会先把文字填回去，看起来像又新增了一次。
    func performWithoutUndo(_ body: () -> Void) {
        let manager = undoManager
        manager?.disableUndoRegistration()
        body()
        discardFocusedTextUndo()
        DispatchQueue.main.async {
            guard manager?.isUndoRegistrationEnabled == false else { return }
            manager?.enableUndoRegistration()
        }
    }

    func setShowsWidgetBadge(_ shows: Bool) {
        do {
            try AppPreferences.saveShowsWidgetBadge(shows)
            showsWidgetBadge = shows
            reloadWidget()
        } catch let error as StoreError {
            notice = error.message
        } catch {
            notice = StoreError.writeFailed.message
        }
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

    private func registerCreation(_ items: [TodoItem], name: String) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        register(name) { store in
            do {
                _ = try store.remove(ids)
                store.register(name) { nested in
                    do {
                        try nested.putBack(items)
                        nested.registerCreation(items, name: name)
                    } catch {
                        nested.fail(error)
                    }
                }
            } catch {
                store.fail(error)
            }
        }
    }

    private func registerRemoval(_ removed: [TodoItem], name: String) {
        register(name) { store in
            do {
                try store.putBack(removed)
                store.register(name) { $0.delete(ids: Set(removed.map(\.id)), actionName: name) }
            } catch {
                store.fail(error)
            }
        }
    }

    private func remove(_ ids: Set<UUID>) throws -> [TodoItem] {
        let removed = try currentRepository().delete(ids: ids)
        reload(animating: removed.count <= 50, fadeRemoval: removed.count > 1)
        return removed
    }

    private func putBack(_ items: [TodoItem]) throws {
        try currentRepository().restore(items)
        reload(animating: true, fadeRemoval: false)
    }

    private func apply(statuses: [UUID: TodoStatus], name: String) {
        let before = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0.status) })
        do {
            let repository = try currentRepository()
            let now = Date()
            for (id, status) in statuses {
                _ = try repository.setStatus(id: id, status: status, now: now)
            }
            reload()
            for id in statuses.keys {
                noteParentsThatJustFinished(previous: before, editedID: id)
            }
            let inverse = Dictionary(uniqueKeysWithValues: statuses.keys.compactMap { id in
                before[id].map { (id, $0) }
            })
            register(name) { $0.apply(statuses: inverse, name: name) }
        } catch {
            fail(error)
        }
    }

    private func revertDeadline(id: UUID, dueDate: String?, dueTime: String?, thenDate: String?, thenTime: String?, name: String) {
        guard writeDeadline(id: id, dueDate: dueDate, dueTime: dueTime) else { return }
        register(name) {
            $0.revertDeadline(id: id, dueDate: thenDate, dueTime: thenTime, thenDate: dueDate, thenTime: dueTime, name: name)
        }
    }

    @discardableResult
    private func writeDeadline(id: UUID, dueDate: String?, dueTime: String?) -> Bool {
        guard let item = document.items.first(where: { $0.id == id }) else { return false }
        do {
            let repository = try currentRepository()
            let edit = TodoEdit(
                base: item,
                title: item.title,
                project: item.project,
                assignee: item.assignee,
                dueDate: dueDate,
                dueTime: dueTime,
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

    private func revertTitle(id: UUID, to title: String, then redo: String, name: String) {
        guard writeTitle(id: id, title: title) else { return }
        register(name) { $0.revertTitle(id: id, to: redo, then: title, name: name) }
    }

    @discardableResult
    private func writeTitle(id: UUID, title: String) -> Bool {
        guard let item = document.items.first(where: { $0.id == id }) else { return false }
        do {
            let repository = try currentRepository()
            let edit = TodoEdit(
                base: item,
                title: title,
                project: item.project,
                assignee: item.assignee,
                dueDate: item.dueDate,
                dueTime: item.dueTime,
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

    private func performMove(id: UUID, before targetID: UUID?, undoBefore: UUID?, name: String) {
        do {
            try currentRepository().move(id: id, before: targetID)
            reload()
            register(name) { $0.performMove(id: id, before: undoBefore, undoBefore: targetID, name: name) }
        } catch {
            fail(error)
        }
    }

    private func register(_ name: String, _ action: @escaping (TaskStore) -> Void) {
        modelUndo.beginUndoGrouping()
        modelUndo.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { action(store) }
        }
        modelUndo.setActionName(name)
        modelUndo.endUndoGrouping()
        undoRevision += 1
    }

    private func discardFocusedTextUndo() {
        guard let undoManager else { return }
        var responder: NSResponder? = mainWindow?.firstResponder
        var steps = 0
        while let current = responder, steps < 8 {
            undoManager.removeAllActions(withTarget: current)
            if let textView = current as? NSTextView {
                if let storage = textView.textStorage {
                    undoManager.removeAllActions(withTarget: storage)
                }
                if let layout = textView.layoutManager {
                    undoManager.removeAllActions(withTarget: layout)
                }
            }
            responder = current.nextResponder
            steps += 1
        }
    }

    private func nextSibling(after id: UUID) -> UUID? {
        guard let moving = document.items.first(where: { $0.id == id }) else { return nil }
        let siblings = orderedSiblings(of: moving.parentID)
        guard let index = siblings.firstIndex(where: { $0.id == id }), index + 1 < siblings.count else { return nil }
        return siblings[index + 1].id
    }

    private func orderedSiblings(of parentID: UUID?) -> [TodoItem] {
        document.items.filter { $0.parentID == parentID }.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func branch(_ item: TodoItem) -> [UUID] {
        [item.id] + orderedSiblings(of: item.id).flatMap(branch)
    }

    private func fail(_ error: Error) {
        if let error = error as? StoreError {
            if case .notFound = error {
                notice = error.message
                reload()
            } else {
                loadError = error
            }
        } else {
            loadError = .writeFailed
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

    private func reload(animating: Bool, fadeRemoval: Bool) {
        animatesListChanges = animating
        fadesRowRemoval = fadeRemoval
        do {
            let repository = try currentRepository()
            adopt(try repository.load())
            loadError = nil
        } catch let error as StoreError {
            adopt(.empty)
            loadError = error
        } catch {
            adopt(.empty)
            loadError = .writeFailed
        }
        reloadWidget()
    }

    private func adopt(_ document: TodoDocument) {
        self.document = document
        let ids = Set(document.items.map(\.id))
        let remaining = selection.intersection(ids)
        if remaining != selection { selection = remaining }
        if let selectionAnchor, !ids.contains(selectionAnchor) {
            self.selectionAnchor = selection.first
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

    private func reloadWidget() {
        AppIdentity.reloadWidgets()
    }
}
