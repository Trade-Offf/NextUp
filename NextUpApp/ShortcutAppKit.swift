import AppKit
import SwiftUI
import NextUpShared

extension ShortcutBinding {
    init?(event: NSEvent) {
        let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeys.contains(event.keyCode) { return nil }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: [ShortcutModifier] = []
        if flags.contains(.control) { modifiers.append(.control) }
        if flags.contains(.option) { modifiers.append(.option) }
        if flags.contains(.shift) { modifiers.append(.shift) }
        if flags.contains(.command) { modifiers.append(.command) }

        let key: String
        switch event.keyCode {
        case 126: key = "up"
        case 125: key = "down"
        case 123: key = "left"
        case 124: key = "right"
        case 36, 76: key = "return"
        case 53: key = "escape"
        case 51: key = "delete"
        case 117: key = "forwardDelete"
        case 49: key = "space"
        case 48: key = "tab"
        case 122: key = "f1"
        case 120: key = "f2"
        case 99: key = "f3"
        case 118: key = "f4"
        case 96: key = "f5"
        case 97: key = "f6"
        case 98: key = "f7"
        case 100: key = "f8"
        case 101: key = "f9"
        case 109: key = "f10"
        case 103: key = "f11"
        case 111: key = "f12"
        default:
            guard let characters = event.charactersIgnoringModifiers?.lowercased(), characters.count == 1 else {
                return nil
            }
            key = characters
        }
        self.init(key: key, modifiers: modifiers)
    }

    var menuKey: KeyEquivalent? {
        switch key {
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "return": return .return
        case "escape": return .escape
        case "delete": return .delete
        case "forwardDelete": return .deleteForward
        case "space": return .space
        case "tab": return .tab
        default:
            guard key.count == 1, let character = key.first else { return nil }
            return KeyEquivalent(character)
        }
    }

    var menuModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}

enum ShortcutRecordingNote: Equatable {
    case reserved
    case conflict(AppCommand, ShortcutBinding)
}
