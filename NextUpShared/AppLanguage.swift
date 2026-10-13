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
    private struct Payload: Codable {
        var language: String
    }

    public static func chosen() -> AppLanguage? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return AppLanguage(rawValue: payload.language)
    }

    public static func save(_ language: AppLanguage) throws {
        let repository = try TodoRepository.localStore()
        let url = repository.directory.appendingPathComponent("preferences.json")
        let data = try JSONEncoder().encode(Payload(language: language.rawValue))
        try data.write(to: url, options: .atomic)
    }

    private static func fileURL() -> URL? {
        guard let repository = try? TodoRepository.localStore() else { return nil }
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
        case widgetDescription
        case unrecognizedLink
        case missingTask
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

    public static func unfinishedLabel(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "接下来，\(count) 项未完成"
        case .english: return "Next Up, \(count) open"
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
        .widgetDescription: "打开通知中心，看接下来最值得关注的几件事。",
        .unrecognizedLink: "这个链接无法识别。",
        .missingTask: "这条任务已经不在了。"
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
        .widgetDescription: "Open Notification Center to see what to do next.",
        .unrecognizedLink: "This link can’t be opened.",
        .missingTask: "That task is already gone."
    ]
}
