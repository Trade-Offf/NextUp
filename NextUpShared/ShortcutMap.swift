import Foundation

public enum AppCommand: String, Codable, CaseIterable, Sendable {
    case undo
    case redo
    case newTask
    case selectPrevious
    case selectNext
    case selectAllTasks
    case clearSelection
    case toggleDone
    case rename
    case moveUp
    case moveDown
    case deleteSelection
    case clearCompleted
}

public enum ShortcutGroup: CaseIterable, Hashable, Sendable {
    case edit
    case tasks

    public var commands: [AppCommand] {
        switch self {
        case .edit:
            return [.undo, .redo]
        case .tasks:
            return [
                .newTask, .selectPrevious, .selectNext, .selectAllTasks, .clearSelection,
                .toggleDone, .rename, .moveUp, .moveDown, .deleteSelection, .clearCompleted
            ]
        }
    }
}

public enum ShortcutModifier: String, Codable, CaseIterable, Sendable {
    case control
    case option
    case shift
    case command
}

public struct ShortcutBinding: Codable, Hashable, Sendable {
    public var key: String
    public var modifiers: [ShortcutModifier]

    public init(key: String, modifiers: [ShortcutModifier] = []) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = ShortcutModifier.allCases.filter { modifiers.contains($0) }
    }

    /// ⌘、⌥、⌃ 在输入时也生效。单独的 Shift 仍留给文字。
    public var worksWhileTyping: Bool {
        modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control)
    }

    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        text += Self.glyph(for: key)
        return text
    }

    private static func glyph(for key: String) -> String {
        switch key {
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        case "return": return "↩"
        case "escape": return "⎋"
        case "delete": return "⌫"
        case "space": return "␣"
        case "tab": return "⇥"
        default:
            if key.count == 1 { return key.uppercased() }
            return key.uppercased()
        }
    }
}

public enum ShortcutCheck: Equatable, Sendable {
    case available
    case reserved
    case conflict(AppCommand)
}

public struct ShortcutMap: Equatable, Sendable {
    private enum Stored: Equatable {
        case set(ShortcutBinding)
        case cleared
    }

    private var stored: [AppCommand: Stored]

    public init() {
        stored = [:]
    }

    public static let defaults: [AppCommand: ShortcutBinding] = [
        .undo: ShortcutBinding(key: "z", modifiers: [.command]),
        .redo: ShortcutBinding(key: "z", modifiers: [.command, .shift]),
        .newTask: ShortcutBinding(key: "n", modifiers: [.command]),
        .selectPrevious: ShortcutBinding(key: "up"),
        .selectNext: ShortcutBinding(key: "down"),
        .selectAllTasks: ShortcutBinding(key: "a", modifiers: [.command]),
        .clearSelection: ShortcutBinding(key: "escape"),
        .toggleDone: ShortcutBinding(key: "space"),
        .rename: ShortcutBinding(key: "return"),
        .moveUp: ShortcutBinding(key: "up", modifiers: [.command, .control]),
        .moveDown: ShortcutBinding(key: "down", modifiers: [.command, .control]),
        .deleteSelection: ShortcutBinding(key: "delete"),
        .clearCompleted: ShortcutBinding(key: "delete", modifiers: [.command, .shift])
    ]

    public static func reserved(_ binding: ShortcutBinding) -> Bool {
        let blocked: [ShortcutBinding] = [
            ShortcutBinding(key: "q", modifiers: [.command]),
            ShortcutBinding(key: "w", modifiers: [.command]),
            ShortcutBinding(key: "h", modifiers: [.command]),
            ShortcutBinding(key: "m", modifiers: [.command]),
            ShortcutBinding(key: "tab", modifiers: [.command]),
            ShortcutBinding(key: ",", modifiers: [.command])
        ]
        return blocked.contains(binding)
    }

    public func binding(for command: AppCommand) -> ShortcutBinding? {
        switch stored[command] {
        case .cleared:
            return nil
        case .set(let binding):
            return binding
        case nil:
            return Self.defaults[command]
        }
    }

    public func check(_ binding: ShortcutBinding, for command: AppCommand) -> ShortcutCheck {
        if Self.reserved(binding) { return .reserved }
        for other in AppCommand.allCases where other != command {
            if binding == self.binding(for: other) { return .conflict(other) }
        }
        return .available
    }

    public mutating func assign(_ binding: ShortcutBinding, to command: AppCommand) {
        if Self.defaults[command] == binding {
            stored[command] = nil
        } else {
            stored[command] = .set(binding)
        }
    }

    public mutating func replace(_ binding: ShortcutBinding, to command: AppCommand, from other: AppCommand) {
        clear(other)
        assign(binding, to: command)
    }

    public mutating func clear(_ command: AppCommand) {
        stored[command] = .cleared
    }

    public mutating func reset() {
        stored = [:]
    }

    var exported: [String: ShortcutBinding?] {
        var result: [String: ShortcutBinding?] = [:]
        for (command, value) in stored {
            switch value {
            case .cleared:
                result.updateValue(nil, forKey: command.rawValue)
            case .set(let binding):
                result.updateValue(binding, forKey: command.rawValue)
            }
        }
        return result
    }

    init(exported: [String: ShortcutBinding?]) {
        var stored: [AppCommand: Stored] = [:]
        for (key, value) in exported {
            guard let command = AppCommand(rawValue: key) else { continue }
            if let value {
                stored[command] = .set(value)
            } else {
                stored[command] = .cleared
            }
        }
        self.stored = stored
    }
}
