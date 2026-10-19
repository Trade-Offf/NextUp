import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case englishAU = "en-AU"
    case french = "fr"
    case japanese = "ja"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .englishAU: return "English (Australia)"
        case .french: return "Français"
        case .japanese: return "日本語"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }

    /// 当前语言的日期习惯：澳洲英语和法语先写日，其余先写月。
    public var writesDayFirst: Bool {
        self == .englishAU || self == .french
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
        let region = locale.language.region?.identifier
        switch code {
        case "en":
            return region == "AU" ? .englishAU : .english
        case "fr":
            return .french
        case "ja":
            return .japanese
        case "zh":
            let script = locale.language.script?.identifier
            if script == "Hant" || ((script == nil) && (region == "TW" || region == "HK" || region == "MO")) {
                return .zhHant
            }
            return .zhHans
        default:
            return nil
        }
    }
}

/// 应用内文字大小。窗口和菜单栏随它缩放，小组件跟随系统卡片，不受影响。
public enum TextSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var scale: Double {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.2
        }
    }
}

public enum AppPreferences {
    /// 测试把读写指到临时文件，避免碰到用户自己的 preferences.json。
    public static var fileOverride: URL?

    private struct Payload: Codable {
        var language: String?
        var shortcuts: [String: OptionalBinding]?
        var showsWidgetBadge: Bool? = nil
        var textSize: String? = nil

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

    public static func textSize() -> TextSize {
        read()?.textSize.flatMap(TextSize.init(rawValue:)) ?? .medium
    }

    public static func save(_ size: TextSize) throws {
        var payload = read() ?? Payload(language: nil, shortcuts: nil)
        payload.textSize = size.rawValue
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
            showsWidgetBadge: object["showsWidgetBadge"] as? Bool,
            textSize: object["textSize"] as? String
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
        guard let repository = try? TodoRepository.inAppGroup() else { return nil }
        return repository.directory.appendingPathComponent("preferences.json")
    }

    private static func preferencesURL() throws -> URL {
        if let fileOverride { return fileOverride }
        let repository = try TodoRepository.inAppGroup()
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
        case emptyHint
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
        case textSize
        case textSizeSmall
        case textSizeMedium
        case textSizeLarge
    }

    private static let nbsp = "\u{00A0}"

    private static func plural(_ count: Int) -> Bool { count != 1 }

    public static func shortcutUsedBy(_ name: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "已用于\(name)"
        case .zhHant: return "已用於\(name)"
        case .english, .englishAU: return "Used by \(name)"
        case .french: return "Déjà utilisé par\(nbsp)\(name)"
        case .japanese: return "「\(name)」で使用中"
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
        let table: [Key: String]
        switch language {
        case .zhHans: table = zhHans
        case .zhHant: table = zhHant
        case .english: table = english
        case .englishAU: table = englishAUOverrides
        case .french: table = french
        case .japanese: table = japanese
        }
        return table[key] ?? english[key] ?? ""
    }

    /// 读屏时把几段信息连起来的分隔符。中日文用全角，其余语言用逗号加空格。
    public static func listSeparator(_ language: AppLanguage) -> String {
        switch language {
        case .zhHans, .zhHant: return "，"
        case .japanese: return "、"
        case .english, .englishAU, .french: return ", "
        }
    }

    public static func openCount(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "\(count) 项"
        case .zhHant: return "\(count) 項"
        case .english, .englishAU: return "\(count) open"
        case .french: return "\(count) à faire"
        case .japanese: return "未完了 \(count) 件"
        }
    }

    public static func widgetMore(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "还有 \(count) 项"
        case .zhHant: return "還有 \(count) 項"
        case .english, .englishAU: return "\(count) more"
        case .french: return "\(count) de plus"
        case .japanese: return "ほか \(count) 件"
        }
    }

    public static func clearConfirmTitle(_ scope: TodoClearing.Scope, _ language: AppLanguage) -> String {
        switch (scope, language) {
        case (.writtenToday, .zhHans): return "清空今日？"
        case (.everything, .zhHans): return "清空所有？"
        case (.writtenToday, .zhHant): return "清空今日？"
        case (.everything, .zhHant): return "清空全部？"
        case (.writtenToday, .english), (.writtenToday, .englishAU): return "Clear Today?"
        case (.everything, .english), (.everything, .englishAU): return "Clear All?"
        case (.writtenToday, .french): return "Effacer aujourd’hui\(nbsp)?"
        case (.everything, .french): return "Tout effacer\(nbsp)?"
        case (.writtenToday, .japanese): return "今日分を消去しますか？"
        case (.everything, .japanese): return "すべて消去しますか？"
        }
    }

    public static func clearWarning(_ scope: TodoClearing.Scope, _ count: Int, _ language: AppLanguage) -> String {
        switch (scope, language) {
        case (.writtenToday, .zhHans): return "将删除今天写入的 \(count) 项，包含子任务。可以回退。"
        case (.everything, .zhHans): return "将删除全部 \(count) 项。可以回退。"
        case (.writtenToday, .zhHant): return "將刪除今天建立的 \(count) 項，包含子任務。可以還原。"
        case (.everything, .zhHant): return "將刪除全部 \(count) 項。可以還原。"
        case (.writtenToday, .english), (.writtenToday, .englishAU):
            return "This deletes the \(count) \(plural(count) ? "items" : "item") written today, including subtasks. You can undo it."
        case (.everything, .english), (.everything, .englishAU):
            return "This deletes all \(count) \(plural(count) ? "items" : "item"). You can undo it."
        case (.writtenToday, .french):
            return "\(count) \(plural(count) ? "éléments créés" : "élément créé") aujourd’hui, sous-tâches comprises, \(plural(count) ? "seront supprimés" : "sera supprimé"). Vous pouvez annuler."
        case (.everything, .french):
            return "\(plural(count) ? "Les \(count) éléments seront supprimés" : "L’élément sera supprimé"). Vous pouvez annuler."
        case (.writtenToday, .japanese):
            return "今日追加した \(count) 件（サブタスクを含む）を削除します。取り消すことができます。"
        case (.everything, .japanese):
            return "\(count) 件すべてを削除します。取り消すことができます。"
        }
    }

    public static func unfinishedLabel(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "接下来，\(count) 项未完成"
        case .zhHant: return "接下來，\(count) 項未完成"
        case .english, .englishAU: return "Next TODO, \(count) open"
        case .french: return "Next TODO, \(count) à faire"
        case .japanese: return "Next TODO、未完了 \(count) 件"
        }
    }

    public static func rollbackTitle(_ action: String, _ language: AppLanguage) -> String {
        guard !action.isEmpty else { return text(.undoLabel, language) }
        switch language {
        case .zhHans: return "回退 \(action)"
        case .zhHant: return "還原 \(action)"
        case .english, .englishAU: return "Undo \(action)"
        case .french: return "Annuler \(action)"
        case .japanese: return "\(action)を取り消す"
        }
    }

    public static func redoTitle(_ action: String, _ language: AppLanguage) -> String {
        guard !action.isEmpty else { return text(.redoLabel, language) }
        switch language {
        case .zhHans: return "重做 \(action)"
        case .zhHant: return "重做 \(action)"
        case .english, .englishAU: return "Redo \(action)"
        case .french: return "Rétablir \(action)"
        case .japanese: return "\(action)をやり直す"
        }
    }

    public static func undoPaste(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "粘贴 \(count) 条"
        case .zhHant: return "貼上 \(count) 項"
        case .english, .englishAU: return count == 1 ? "Paste 1 Item" : "Paste \(count) Items"
        case .french: return count == 1 ? "Coller 1 élément" : "Coller \(count) éléments"
        case .japanese: return "\(count) 件を貼り付け"
        }
    }

    public static func undoDelete(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "删除 \(count) 项"
        case .zhHant: return "刪除 \(count) 項"
        case .english, .englishAU: return count == 1 ? "Delete 1 Item" : "Delete \(count) Items"
        case .french: return count == 1 ? "Supprimer 1 élément" : "Supprimer \(count) éléments"
        case .japanese: return "\(count) 件を削除"
        }
    }

    public static func pendingPaste(_ count: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "将添加 \(count) 条"
        case .zhHant: return "將新增 \(count) 項"
        case .english, .englishAU: return count == 1 ? "Adds 1 item" : "Adds \(count) items"
        case .french: return count == 1 ? "Ajoute 1 tâche" : "Ajoute \(count) tâches"
        case .japanese: return "\(count) 件を追加します"
        }
    }

    public static func complete(_ title: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "完成：\(title)"
        case .zhHant: return "完成：\(title)"
        case .english, .englishAU: return "Complete: \(title)"
        case .french: return "Terminer\(nbsp): \(title)"
        case .japanese: return "完了：\(title)"
        }
    }

    public static func reopen(_ title: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "重新打开：\(title)"
        case .zhHant: return "重新開啟：\(title)"
        case .english, .englishAU: return "Reopen: \(title)"
        case .french: return "Rouvrir\(nbsp): \(title)"
        case .japanese: return "未完了に戻す：\(title)"
        }
    }

    public static func completedItem(_ title: String, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "已完成：\(title)"
        case .zhHant: return "已完成：\(title)"
        case .english, .englishAU: return "Completed: \(title)"
        case .french: return "Terminé\(nbsp): \(title)"
        case .japanese: return "完了済み：\(title)"
        }
    }

    public static func unsupportedSchema(found: Int, supported: Int, _ language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "数据版本 \(found) 不受支持（当前支持 \(supported)）。未改写原文件。"
        case .zhHant:
            return "資料版本 \(found) 不受支援（目前支援 \(supported)）。未改寫原始檔案。"
        case .english, .englishAU:
            return "Data version \(found) isn’t supported (this app supports \(supported)). The original file was left unchanged."
        case .french:
            return "La version des données (\(found)) n’est pas prise en charge (version prise en charge\(nbsp): \(supported)). Le fichier d’origine n’a pas été modifié."
        case .japanese:
            return "データのバージョン \(found) には対応していません（対応バージョン：\(supported)）。元のファイルは変更されていません。"
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
        .addSubtask: "添加子任务",
        .edit: "编辑",
        .delete: "删除",
        .title: "标题",
        .menuPlaceholder: "记下下一件事…",
        .openApp: "打开 Next TODO",
        .quitApp: "退出 Next TODO",
        .allDone: "都处理好了",
        .tapToOpen: "点击打开 Next TODO",
        .allDoneHint: "都处理好了。点击打开 Next TODO",
        .readFailed: "暂时无法读取任务",
        .readFailedHint: "暂时无法读取任务。点击打开 Next TODO",
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
        .emptyHint: "回车添加。粘贴多行大纲，一次建好多条任务。",
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
        .redoLabel: "重做",
        .textSize: "文字大小",
        .textSizeSmall: "小",
        .textSizeMedium: "中",
        .textSizeLarge: "大"
    ]

    private static let zhHant: [Key: String] = [
        .windowTitle: "接下來",
        .completed: "已完成",
        .composerPlaceholder: "新增任務，可貼上大綱",
        .subtask: "子任務",
        .add: "新增",
        .addSubtask: "新增子任務",
        .edit: "編輯",
        .delete: "刪除",
        .title: "標題",
        .menuPlaceholder: "記下下一件事…",
        .openApp: "開啟 Next TODO",
        .quitApp: "結束 Next TODO",
        .allDone: "都處理好了",
        .tapToOpen: "點一下以開啟 Next TODO",
        .allDoneHint: "都處理好了。點一下以開啟 Next TODO",
        .readFailed: "暫時無法讀取任務",
        .readFailedHint: "暫時無法讀取任務。點一下以開啟 Next TODO",
        .overdue: "已逾期",
        .today: "今天",
        .waiting: "等待回覆",
        .settings: "設定",
        .general: "一般",
        .language: "語言",
        .restoreBackup: "從最近的備份復原",
        .ok: "好",
        .notice: "提示",
        .containerUnavailable: "無法存取本機任務資料。",
        .corrupted: "任務資料已損毀，原始檔案已保留。",
        .notFound: "任務不存在或已被刪除。",
        .invalidTitle: "標題不能空白，且不能超過 200 個字元。",
        .invalidDueDate: "截止日期無效。",
        .writeFailed: "儲存失敗，請再試一次。",
        .backupUnavailable: "沒有可用的備份。",
        .restoreNotNeeded: "目前的資料可以讀取，未使用備份覆蓋。",
        .restored: "已從最近的備份復原。",
        .widgetCountName: "還剩多少",
        .widgetCountDescription: "逾期、今天、之後、未排程",
        .widgetListName: "接下來",
        .widgetListDescription: "依日期列出",
        .unrecognizedLink: "無法辨識這個連結。",
        .missingTask: "這項任務已經不在了。",
        .undoAdd: "新增任務",
        .undoComplete: "完成",
        .undoReopen: "重新開啟",
        .undoRename: "重新命名",
        .undoMove: "調整順序",
        .undoDeadline: "設定截止時間",
        .deadline: "截止時間",
        .dueToday: "今日",
        .pickDateTime: "選擇日期和時間…",
        .clearDeadline: "清除截止時間",
        .tasksMenu: "任務",
        .newTask: "新增任務",
        .selectAllTasks: "選取全部任務",
        .selectPrevious: "選取上一項",
        .selectNext: "選取下一項",
        .deleteSelection: "刪除所選項目",
        .clearCompleted: "清除已完成項目",
        .toggleDone: "完成或重新開啟",
        .rename: "重新命名",
        .moveUp: "上移",
        .moveDown: "下移",
        .clearSelection: "取消選取",
        .pasteHint: "按下 Return 新增，Esc 取消",
        .emptyHint: "按下 Return 新增。貼上多行大綱，一次建立多項任務。",
        .dataSection: "資料",
        .clearToday: "清空今日",
        .clearHistory: "清空全部",
        .cancel: "取消",
        .widgetOpenItems: "項未完成",
        .widgetUpcoming: "之後",
        .widgetUndated: "未排程",
        .showWidgetBadge: "顯示小工具徽章",
        .shortcuts: "鍵盤快速鍵",
        .customizeShortcuts: "自訂",
        .pressShortcut: "請按下快速鍵",
        .restoreDefaults: "還原預設值",
        .shortcutDone: "完成",
        .shortcutReserved: "系統保留",
        .shortcutReplace: "取代",
        .shortcutGroupEdit: "編輯",
        .noShortcut: "無",
        .undoLabel: "還原",
        .redoLabel: "重做",
        .textSize: "文字大小",
        .textSizeSmall: "小",
        .textSizeMedium: "中",
        .textSizeLarge: "大"
    ]

    private static let english: [Key: String] = [
        .windowTitle: "Next TODO",
        .completed: "Completed",
        .composerPlaceholder: "New task, or paste an outline",
        .subtask: "Subtask",
        .add: "Add",
        .addSubtask: "Add a subtask",
        .edit: "Edit",
        .delete: "Delete",
        .title: "Title",
        .menuPlaceholder: "Add what’s next…",
        .openApp: "Open Next TODO",
        .quitApp: "Quit Next TODO",
        .allDone: "All done",
        .tapToOpen: "Click to open Next TODO",
        .allDoneHint: "All done. Click to open Next TODO",
        .readFailed: "Can’t read tasks right now",
        .readFailedHint: "Can’t read tasks right now. Click to open Next TODO",
        .overdue: "Overdue",
        .today: "Today",
        .waiting: "Waiting",
        .settings: "Settings",
        .general: "General",
        .language: "Language",
        .restoreBackup: "Restore from the Latest Backup",
        .ok: "OK",
        .notice: "Notice",
        .containerUnavailable: "Can’t access your local tasks.",
        .corrupted: "Task data is damaged. The original file was kept.",
        .notFound: "That task no longer exists.",
        .invalidTitle: "The title can’t be empty or longer than 200 characters.",
        .invalidDueDate: "That due date isn’t valid.",
        .writeFailed: "Couldn’t save. Try again.",
        .backupUnavailable: "No backup is available.",
        .restoreNotNeeded: "Your current data can be read, so the backup wasn’t used.",
        .restored: "Restored from the latest backup.",
        .widgetCountName: "What’s Left",
        .widgetCountDescription: "Overdue, today, later, unscheduled",
        .widgetListName: "Next TODO",
        .widgetListDescription: "Listed by date",
        .unrecognizedLink: "This link can’t be opened.",
        .missingTask: "That task no longer exists.",
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
        .emptyHint: "Press Return to add. Paste a multi-line outline to create several tasks at once.",
        .dataSection: "Data",
        .clearToday: "Clear Today",
        .clearHistory: "Clear All",
        .cancel: "Cancel",
        .widgetOpenItems: "open",
        .widgetUpcoming: "Later",
        .widgetUndated: "Unscheduled",
        .showWidgetBadge: "Show Widget Badge",
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
        .redoLabel: "Redo",
        .textSize: "Text Size",
        .textSizeSmall: "Small",
        .textSizeMedium: "Medium",
        .textSizeLarge: "Large"
    ]

    /// 澳洲英语只改拼写不同的词，其余沿用英语。
    private static let englishAUOverrides: [Key: String] = {
        var table = english
        table[.customizeShortcuts] = "Customise"
        return table
    }()

    private static let french: [Key: String] = [
        .windowTitle: "Next TODO",
        .completed: "Terminées",
        .composerPlaceholder: "Nouvelle tâche, ou collez un plan",
        .subtask: "Sous-tâche",
        .add: "Ajouter",
        .addSubtask: "Ajouter une sous-tâche",
        .edit: "Modifier",
        .delete: "Supprimer",
        .title: "Titre",
        .menuPlaceholder: "Noter la prochaine tâche…",
        .openApp: "Ouvrir Next TODO",
        .quitApp: "Quitter Next TODO",
        .allDone: "Tout est fait",
        .tapToOpen: "Cliquez pour ouvrir Next TODO",
        .allDoneHint: "Tout est fait. Cliquez pour ouvrir Next TODO",
        .readFailed: "Impossible de lire les tâches pour le moment",
        .readFailedHint: "Impossible de lire les tâches pour le moment. Cliquez pour ouvrir Next TODO",
        .overdue: "En retard",
        .today: "Aujourd’hui",
        .waiting: "En attente",
        .settings: "Réglages",
        .general: "Général",
        .language: "Langue",
        .restoreBackup: "Restaurer la dernière sauvegarde",
        .ok: "OK",
        .notice: "Information",
        .containerUnavailable: "Impossible d’accéder à vos tâches locales.",
        .corrupted: "Les données des tâches sont endommagées. Le fichier d’origine a été conservé.",
        .notFound: "Cette tâche n’existe plus.",
        .invalidTitle: "Le titre ne peut pas être vide ni dépasser 200 caractères.",
        .invalidDueDate: "Cette échéance n’est pas valide.",
        .writeFailed: "Enregistrement impossible. Réessayez.",
        .backupUnavailable: "Aucune sauvegarde disponible.",
        .restoreNotNeeded: "Les données actuelles sont lisibles, la sauvegarde n’a donc pas été utilisée.",
        .restored: "Restauré depuis la dernière sauvegarde.",
        .widgetCountName: "Ce qu’il reste",
        .widgetCountDescription: "En retard, aujourd’hui, plus tard, non planifié",
        .widgetListName: "Next TODO",
        .widgetListDescription: "Classées par date",
        .unrecognizedLink: "Ce lien ne peut pas être ouvert.",
        .missingTask: "Cette tâche n’existe plus.",
        .undoAdd: "Ajout de la tâche",
        .undoComplete: "Terminer",
        .undoReopen: "Rouvrir",
        .undoRename: "Renommer",
        .undoMove: "Réorganiser",
        .undoDeadline: "Définir l’échéance",
        .deadline: "Échéance",
        .dueToday: "Aujourd’hui",
        .pickDateTime: "Choisir la date et l’heure…",
        .clearDeadline: "Supprimer l’échéance",
        .tasksMenu: "Tâches",
        .newTask: "Nouvelle tâche",
        .selectAllTasks: "Sélectionner toutes les tâches",
        .selectPrevious: "Sélectionner la précédente",
        .selectNext: "Sélectionner la suivante",
        .deleteSelection: "Supprimer la sélection",
        .clearCompleted: "Effacer les tâches terminées",
        .toggleDone: "Terminer ou rouvrir",
        .rename: "Renommer",
        .moveUp: "Monter",
        .moveDown: "Descendre",
        .clearSelection: "Tout désélectionner",
        .pasteHint: "Retour pour ajouter, Échap pour annuler",
        .emptyHint: "Appuyez sur Retour pour ajouter. Collez un plan de plusieurs lignes pour créer plusieurs tâches d’un coup.",
        .dataSection: "Données",
        .clearToday: "Effacer aujourd’hui",
        .clearHistory: "Tout effacer",
        .cancel: "Annuler",
        .widgetOpenItems: "à faire",
        .widgetUpcoming: "Plus tard",
        .widgetUndated: "Non planifié",
        .showWidgetBadge: "Afficher le badge du widget",
        .shortcuts: "Raccourcis clavier",
        .customizeShortcuts: "Personnaliser",
        .pressShortcut: "Saisissez un raccourci",
        .restoreDefaults: "Rétablir les valeurs par défaut",
        .shortcutDone: "OK",
        .shortcutReserved: "Réservé par le système",
        .shortcutReplace: "Remplacer",
        .shortcutGroupEdit: "Édition",
        .noShortcut: "Aucun",
        .undoLabel: "Annuler",
        .redoLabel: "Rétablir",
        .textSize: "Taille du texte",
        .textSizeSmall: "Petite",
        .textSizeMedium: "Moyenne",
        .textSizeLarge: "Grande"
    ]

    private static let japanese: [Key: String] = [
        .windowTitle: "Next TODO",
        .completed: "完了済み",
        .composerPlaceholder: "新しいタスク（アウトラインの貼り付けも可）",
        .subtask: "サブタスク",
        .add: "追加",
        .addSubtask: "サブタスクを追加",
        .edit: "編集",
        .delete: "削除",
        .title: "タイトル",
        .menuPlaceholder: "次にやることを入力…",
        .openApp: "Next TODO を開く",
        .quitApp: "Next TODO を終了",
        .allDone: "すべて完了",
        .tapToOpen: "クリックして Next TODO を開く",
        .allDoneHint: "すべて完了しました。クリックして Next TODO を開く",
        .readFailed: "タスクを読み込めません",
        .readFailedHint: "タスクを読み込めません。クリックして Next TODO を開く",
        .overdue: "期限切れ",
        .today: "今日",
        .waiting: "返答待ち",
        .settings: "設定",
        .general: "一般",
        .language: "言語",
        .restoreBackup: "最新のバックアップから復元",
        .ok: "OK",
        .notice: "お知らせ",
        .containerUnavailable: "ローカルのタスクデータにアクセスできません。",
        .corrupted: "タスクデータが破損しています。元のファイルは保持されています。",
        .notFound: "このタスクは存在しないか、削除されました。",
        .invalidTitle: "タイトルは空にできず、200 文字以内で入力してください。",
        .invalidDueDate: "期限の日付が正しくありません。",
        .writeFailed: "保存できませんでした。もう一度お試しください。",
        .backupUnavailable: "利用できるバックアップがありません。",
        .restoreNotNeeded: "現在のデータは読み込めるため、バックアップは使用しませんでした。",
        .restored: "最新のバックアップから復元しました。",
        .widgetCountName: "残りの数",
        .widgetCountDescription: "期限切れ・今日・今後・未設定",
        .widgetListName: "Next TODO",
        .widgetListDescription: "日付順に表示",
        .unrecognizedLink: "このリンクは開けません。",
        .missingTask: "このタスクはすでに存在しません。",
        .undoAdd: "タスクの追加",
        .undoComplete: "完了",
        .undoReopen: "未完了に戻す",
        .undoRename: "名前の変更",
        .undoMove: "並べ替え",
        .undoDeadline: "期限の設定",
        .deadline: "期限",
        .dueToday: "今日",
        .pickDateTime: "日付と時刻を選択…",
        .clearDeadline: "期限を解除",
        .tasksMenu: "タスク",
        .newTask: "新規タスク",
        .selectAllTasks: "すべてのタスクを選択",
        .selectPrevious: "前を選択",
        .selectNext: "次を選択",
        .deleteSelection: "選択項目を削除",
        .clearCompleted: "完了済みを消去",
        .toggleDone: "完了／未完了を切り替え",
        .rename: "名前を変更",
        .moveUp: "上へ移動",
        .moveDown: "下へ移動",
        .clearSelection: "選択を解除",
        .pasteHint: "Return で追加、Esc でキャンセル",
        .emptyHint: "Return を押して追加します。複数行のアウトラインを貼り付けると、まとめてタスクを作成できます。",
        .dataSection: "データ",
        .clearToday: "今日分を消去",
        .clearHistory: "すべて消去",
        .cancel: "キャンセル",
        .widgetOpenItems: "件が未完了",
        .widgetUpcoming: "今後",
        .widgetUndated: "未設定",
        .showWidgetBadge: "ウィジェットにバッジを表示",
        .shortcuts: "キーボードショートカット",
        .customizeShortcuts: "カスタマイズ",
        .pressShortcut: "ショートカットを入力",
        .restoreDefaults: "初期設定に戻す",
        .shortcutDone: "完了",
        .shortcutReserved: "システムで予約済み",
        .shortcutReplace: "置き換える",
        .shortcutGroupEdit: "編集",
        .noShortcut: "なし",
        .undoLabel: "取り消す",
        .redoLabel: "やり直す",
        .textSize: "文字サイズ",
        .textSizeSmall: "小",
        .textSizeMedium: "中",
        .textSizeLarge: "大"
    ]
}
