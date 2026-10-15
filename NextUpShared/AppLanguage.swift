import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case zhHans = "zh-Hans"
    case english = "en"

    public var nativeName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }

    public static var resolved: AppLanguage {
        if let chosen = AppPreferences.chosen() { return chosen }
        return matching(Locale.preferredLanguages)
    }

    public static func matching(_ identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            if let language = match(identifier) { return language }
        }
        return .english
    }

    public static func match(_ identifier: String) -> AppLanguage? {
        let locale = Locale(identifier: identifier.replacingOccurrences(of: "_", with: "-"))
        let code = locale.language.languageCode?.identifier
        if code == "en" { return .english }
        if code == "zh" {
            let script = locale.language.script?.identifier
            let region = locale.language.region?.identifier
            if script == "Hant" || region == "TW" || region == "HK" || region == "MO" {
                return nil
            }
            return .zhHans
        }
        return nil
    }
}

public enum AppPreferences {
    /// 测试把读写指到临时文件，避免碰到用户自己的 preferences.json。
    public static var fileOverride: URL?

    private struct Payload: Codable {
        var language: String?
        var shortcuts: [String: OptionalBinding]?
        var showsWidgetBadge: Bool? = nil

        struct OptionalBinding: Codable {
            var value: ShortcutBinding?

            init(value: ShortcutBinding?) {
                self.value = value
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    value = nil
                } else {
                    value = try ShortcutBinding(from: decoder)
                }
            }

            func encode(to encoder: Encoder) throws {
                if let value {
                    try value.encode(to: encoder)
                } else {
                    var container = encoder.singleValueContainer()
                    try container.encodeNil()
                }
            }
        }
    }

    public static func chosen() -> AppLanguage? {
        guard let raw = read()?.language else { return nil }
        return AppLanguage(rawValue: raw)
    }

    /// 缺省关闭。中号小组件保持系统卡片的样子，想看柴犬的人再打开。
    public static func showsWidgetBadge() -> Bool {
        read()?.showsWidgetBadge ?? false
    }

    public static func shortcutMap() -> ShortcutMap {
        guard let shortcuts = read()?.shortcuts else { return ShortcutMap() }
        var exported: [String: ShortcutBinding?] = [:]
        for (key, box) in shortcuts {
            exported.updateValue(box.value, forKey: key)
        }
        return ShortcutMap(exported: exported)
    }

    public static func save(_ language: AppLanguage) throws {
        var payload = read() ?? Payload(language: nil, shortcuts: nil)
        payload.language = language.rawValue
        try write(payload)
    }

    public static func save(_ map: ShortcutMap) throws {
        var payload = read() ?? Payload(language: nil, shortcuts: nil)
        var shortcuts: [String: Payload.OptionalBinding] = [:]
        for (key, value) in map.exported {
            shortcuts[key] = Payload.OptionalBinding(value: value)
        }
        payload.shortcuts = shortcuts
        try write(payload)
    }

    public static func saveShowsWidgetBadge(_ shows: Bool) throws {
        var payload = read() ?? Payload(language: nil, shortcuts: nil)
        payload.showsWidgetBadge = shows
        try write(payload)
    }

    private static func read() -> Payload? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Payload(
            language: object["language"] as? String,
            shortcuts: bindings(from: object["shortcuts"]),
            showsWidgetBadge: object["showsWidgetBadge"] as? Bool
        )
    }

    /// 某一条键位写坏时丢掉这一条，语言和其余键位还在。
    private static func bindings(from value: Any?) -> [String: Payload.OptionalBinding]? {
        guard let raw = value as? [String: Any] else { return nil }
        var shortcuts: [String: Payload.OptionalBinding] = [:]
        for (key, entry) in raw {
            if entry is NSNull {
                shortcuts[key] = Payload.OptionalBinding(value: nil)
                continue
            }
            guard JSONSerialization.isValidJSONObject(entry),
                  let data = try? JSONSerialization.data(withJSONObject: entry),
                  let binding = try? JSONDecoder().decode(ShortcutBinding.self, from: data) else {
                continue
            }
            shortcuts[key] = Payload.OptionalBinding(value: binding)
        }
        return shortcuts
    }

    private static func write(_ payload: Payload) throws {
        let url = try preferencesURL()
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
    }

    private static func fileURL() -> URL? {
        if let fileOverride { return fileOverride }
        guard let repository = try? TodoRepository.localStore() else { return nil }
        return repository.directory.appendingPathComponent("preferences.json")
    }

    private static func preferencesURL() throws -> URL {
        if let fileOverride { return fileOverride }
        let repository = try TodoRepository.localStore()
        return repository.directory.appendingPathComponent("preferences.json")
    }
}

public enum Copy {
    public enum Key: Sendable {
        case windowTitle
        case completed
        case composerPlaceholder
        case subtask
        case add
        case addSubtask
        case edit
        case delete
        case title
        case menuPlaceholder
        case openApp
        case quitApp
        case allDone
        case tapToOpen
        case allDoneHint
        case readFailed
        case readFailedHint
        case overdue
        case today
        case waiting
        case settings
        case general
        case language
        case restoreBackup
        case ok
        case notice
        case containerUnavailable
        case corrupted
        case notFound
        case invalidTitle
        case invalidDueDate
        case writeFailed
        case backupUnavailable
        case restoreNotNeeded
        case restored
        case widgetCountName
        case widgetCountDescription
        case widgetListName
        case widgetListDescription
        case unrecognizedLink
        case missingTask
        case undoAdd
        case undoComplete
        case undoReopen
        case undoRename
        case undoMove
        case undoDeadline
        case deadline
        case dueToday
        case pickDateTime
        case clearDeadline
        case tasksMenu
        case newTask
        case selectAllTasks
        case selectPrevious
        case selectNext
        case deleteSelection
        case clearCompleted
        case toggleDone
        case rename
        case moveUp
        case moveDown
        case clearSelection
        case pasteHint
        case dataSection
        case clearToday
        case clearHistory
        case cancel
        case widgetOpenItems
        case widgetUpcoming
        case widgetUndated
        case showWidgetBadge
        case shortcuts
        case customizeShortcuts
        case pressShortcut
        case restoreDefaults
        case shortcutDone
        case shortcutReserved
        case shortcutReplace
        case shortcutGroupEdit
        case noShortcut
        case undoLabel
        case redoLabel
    }

    public static func shortcutUsedBy(_ name: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "已用于\(name)"
        case .english: return "Used by \(name)"
        }
    }

    public static func shortcutTitle(_ command: AppCommand, _ language: AppLanguage) -> String {
        switch command {
        case .undo: return text(.undoLabel, language)
        case .redo: return text(.redoLabel, language)
        case .newTask: return text(.newTask, language)
        case .selectPrevious: return text(.selectPrevious, language)
        case .selectNext: return text(.selectNext, language)
        case .selectAllTasks: return text(.selectAllTasks, language)
        case .clearSelection: return text(.clearSelection, language)
        case .toggleDone: return text(.toggleDone, language)
        case .rename: return text(.rename, language)
        case .moveUp: return text(.moveUp, language)
        case .moveDown: return text(.moveDown, language)
        case .deleteSelection: return text(.deleteSelection, language)
        case .clearCompleted: return text(.clearCompleted, language)
        }
    }

    public static func text(_ key: Key, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return zhHans[key] ?? english[key] ?? ""
        case .english: return english[key] ?? ""
        }
    }

    public static func openCount(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "\(count) 项"
        case .english: return "\(count) open"
        }
    }

    public static func widgetMore(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "还有 \(count) 项"
        case .english: return "\(count) more"
        }
    }

    public static func clearConfirmTitle(_ scope: TodoClearing.Scope, _ language: AppLanguage) -> String {
        switch (scope, language) {
        case (.writtenToday, .zhHans): return "清空今日？"
        case (.everything, .zhHans): return "清空所有？"
        case (.writtenToday, .english): return "Clear Today?"
        case (.everything, .english): return "Clear All?"
        }
    }

    public static func clearWarning(_ scope: TodoClearing.Scope, _ count: Int, _ language: AppLanguage) -> String {
        switch (scope, language) {
        case (.writtenToday, .zhHans): return "将删除今天写入的 \(count) 项，包含子任务。可以回退。"
        case (.everything, .zhHans): return "将删除全部 \(count) 项。可以回退。"
        case (.writtenToday, .english): return "This deletes the \(count) items written today, including subtasks. You can undo it."
        case (.everything, .english): return "This deletes all \(count) items. You can undo it."
        }
    }

    public static func unfinishedLabel(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "接下来，\(count) 项未完成"
        case .english: return "Next Up, \(count) open"
        }
    }

    public static func rollbackTitle(_ action: String, _ language: AppLanguage) -> String {
        guard !action.isEmpty else {
            return language == .zhHans ? "回退" : "Undo"
        }
        return language == .zhHans ? "回退 \(action)" : "Undo \(action)"
    }

    public static func redoTitle(_ action: String, _ language: AppLanguage) -> String {
        guard !action.isEmpty else {
            return language == .zhHans ? "重做" : "Redo"
        }
        return language == .zhHans ? "重做 \(action)" : "Redo \(action)"
    }

    public static func undoPaste(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "粘贴 \(count) 条"
        case .english: return count == 1 ? "Paste 1 Item" : "Paste \(count) Items"
        }
    }

    public static func undoDelete(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "删除 \(count) 项"
        case .english: return count == 1 ? "Delete 1 Item" : "Delete \(count) Items"
        }
    }

    public static func pendingPaste(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "将添加 \(count) 条"
        case .english: return "Adds \(count) items"
        }
    }

    public static func complete(_ title: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "完成：\(title)"
        case .english: return "Complete: \(title)"
        }
    }

    public static func reopen(_ title: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "重新打开：\(title)"
        case .english: return "Reopen: \(title)"
        }
    }

    public static func completedItem(_ title: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "已完成：\(title)"
        case .english: return "Completed: \(title)"
        }
    }

    public static func unsupportedSchema(found: Int, supported: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "数据版本 \(found) 不受支持（当前支持 \(supported)）。未改写原文件。"
        case .english:
            return "Data version \(found) isn’t supported (this app supports \(supported)). The original file was left unchanged."
        }
    }

    public static func storeError(_ error: StoreError, _ language: AppLanguage) -> String {
        switch error {
        case .containerUnavailable: return text(.containerUnavailable, language)
        case .corrupted: return text(.corrupted, language)
        case .unsupportedSchema(let found, let supported):
            return unsupportedSchema(found: found, supported: supported, language)
        case .notFound: return text(.notFound, language)
        case .invalidTitle: return text(.invalidTitle, language)
        case .invalidDueDate: return text(.invalidDueDate, language)
        case .writeFailed: return text(.writeFailed, language)
        case .backupUnavailable: return text(.backupUnavailable, language)
        case .restoreNotNeeded: return text(.restoreNotNeeded, language)
        }
    }

    private static let zhHans: [Key: String] = [
        .windowTitle: "接下来",
        .completed: "已完成",
        .composerPlaceholder: "新任务，可粘贴大纲",
        .subtask: "子任务",
        .add: "添加",
        .addSubtask: "添加子条目",
        .edit: "编辑",
        .delete: "删除",
        .title: "标题",
        .menuPlaceholder: "记下下一件事…",
        .openApp: "打开 Next Up",
        .quitApp: "退出 Next Up",
        .allDone: "都处理好了",
        .tapToOpen: "点击打开 Next Up",
        .allDoneHint: "都处理好了。点击打开 Next Up",
        .readFailed: "暂时无法读取任务",
        .readFailedHint: "暂时无法读取任务。点击打开 Next Up",
        .overdue: "已逾期",
        .today: "今天",
        .waiting: "等待反馈",
        .settings: "设置",
        .general: "通用",
        .language: "语言",
        .restoreBackup: "从最近的备份恢复",
        .ok: "好",
        .notice: "提示",
        .containerUnavailable: "无法访问本地任务数据。",
        .corrupted: "任务数据已损坏，原文件已保留。",
        .notFound: "任务不存在或已被删除。",
        .invalidTitle: "标题不能为空，且不能超过 200 个字符。",
        .invalidDueDate: "截止日期无效。",
        .writeFailed: "保存失败，请重试。",
        .backupUnavailable: "没有可用的备份。",
        .restoreNotNeeded: "当前数据可以读取，未用备份覆盖。",
        .restored: "已从最近的备份恢复。",
        .widgetCountName: "还剩多少",
        .widgetCountDescription: "逾期、今天、以后、未排期",
        .widgetListName: "接下来",
        .widgetListDescription: "按日期列出",
        .unrecognizedLink: "这个链接无法识别。",
        .missingTask: "这条任务已经不在了。",
        .undoAdd: "添加任务",
        .undoComplete: "完成",
        .undoReopen: "重新打开",
        .undoRename: "重命名",
        .undoMove: "调整顺序",
        .undoDeadline: "设置截止时间",
        .deadline: "截止时间",
        .dueToday: "今日",
        .pickDateTime: "选择日期和时间…",
        .clearDeadline: "清除截止时间",
        .tasksMenu: "任务",
        .newTask: "新任务",
        .selectAllTasks: "选择全部任务",
        .selectPrevious: "选择上一项",
        .selectNext: "选择下一项",
        .deleteSelection: "删除所选",
        .clearCompleted: "清除已完成",
        .toggleDone: "完成或重新打开",
        .rename: "重命名",
        .moveUp: "上移",
        .moveDown: "下移",
        .clearSelection: "取消选择",
        .pasteHint: "回车添加，Esc 取消",
        .dataSection: "数据",
        .clearToday: "清空今日",
        .clearHistory: "清空所有",
        .cancel: "取消",
        .widgetOpenItems: "项未完成",
        .widgetUpcoming: "以后",
        .widgetUndated: "未排期",
        .showWidgetBadge: "显示徽章",
        .shortcuts: "快捷键",
        .customizeShortcuts: "自定义",
        .pressShortcut: "请按下快捷键",
        .restoreDefaults: "恢复默认",
        .shortcutDone: "完成",
        .shortcutReserved: "系统保留",
        .shortcutReplace: "替换",
        .shortcutGroupEdit: "编辑",
        .noShortcut: "无",
        .undoLabel: "回退",
        .redoLabel: "重做"
    ]

    private static let english: [Key: String] = [
        .windowTitle: "Next Up",
        .completed: "Completed",
        .composerPlaceholder: "New task, paste an outline",
        .subtask: "Subtask",
        .add: "Add",
        .addSubtask: "Add a subtask",
        .edit: "Edit",
        .delete: "Delete",
        .title: "Title",
        .menuPlaceholder: "Note the next thing…",
        .openApp: "Open Next Up",
        .quitApp: "Quit Next Up",
        .allDone: "All done",
        .tapToOpen: "Click to open Next Up",
        .allDoneHint: "All done. Click to open Next Up",
        .readFailed: "Can’t read tasks right now",
        .readFailedHint: "Can’t read tasks right now. Click to open Next Up",
        .overdue: "Overdue",
        .today: "Today",
        .waiting: "Waiting",
        .settings: "Settings",
        .general: "General",
        .language: "Language",
        .restoreBackup: "Restore from the latest backup",
        .ok: "OK",
        .notice: "Notice",
        .containerUnavailable: "Can’t read local tasks.",
        .corrupted: "Task data is damaged. The original file was kept.",
        .notFound: "That task is gone.",
        .invalidTitle: "The title can’t be empty or longer than 200 characters.",
        .invalidDueDate: "That due date isn’t valid.",
        .writeFailed: "Couldn’t save. Try again.",
        .backupUnavailable: "No backup is available.",
        .restoreNotNeeded: "The current data can be read, so the backup was left in place.",
        .restored: "Restored from the latest backup.",
        .widgetCountName: "What's Left",
        .widgetCountDescription: "Overdue, today, later, none",
        .widgetListName: "Next Up",
        .widgetListDescription: "By date",
        .unrecognizedLink: "This link can’t be opened.",
        .missingTask: "That task is already gone.",
        .undoAdd: "Add Task",
        .undoComplete: "Complete",
        .undoReopen: "Reopen",
        .undoRename: "Rename",
        .undoMove: "Reorder",
        .undoDeadline: "Set Deadline",
        .deadline: "Deadline",
        .dueToday: "Today",
        .pickDateTime: "Choose Date and Time…",
        .clearDeadline: "Clear Deadline",
        .tasksMenu: "Tasks",
        .newTask: "New Task",
        .selectAllTasks: "Select All Tasks",
        .selectPrevious: "Select Previous",
        .selectNext: "Select Next",
        .deleteSelection: "Delete Selected",
        .clearCompleted: "Clear Completed",
        .toggleDone: "Complete or Reopen",
        .rename: "Rename",
        .moveUp: "Move Up",
        .moveDown: "Move Down",
        .clearSelection: "Deselect",
        .pasteHint: "Return to add, Esc to cancel",
        .dataSection: "Data",
        .clearToday: "Clear Today",
        .clearHistory: "Clear All",
        .cancel: "Cancel",
        .widgetOpenItems: "open",
        .widgetUpcoming: "Later",
        .widgetUndated: "Unscheduled",
        .showWidgetBadge: "Show Badge",
        .shortcuts: "Keyboard Shortcuts",
        .customizeShortcuts: "Customize",
        .pressShortcut: "Type a shortcut",
        .restoreDefaults: "Reset to Defaults",
        .shortcutDone: "Done",
        .shortcutReserved: "Reserved by the system",
        .shortcutReplace: "Replace",
        .shortcutGroupEdit: "Edit",
        .noShortcut: "None",
        .undoLabel: "Undo",
        .redoLabel: "Redo"
    ]
}
