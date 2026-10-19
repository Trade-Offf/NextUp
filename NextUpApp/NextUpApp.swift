import SwiftUI
import NextUpShared

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// 设置里选的文字大小倍数。
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

@main
struct NextUpApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .environment(\.textScale, CGFloat(store.textSize.scale))
        }
        .defaultSize(width: AppWindowMetrics.width, height: AppWindowMetrics.height)
        .commands {
            UndoCommands(store: store)
            TaskCommands(store: store)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
        .defaultSize(width: AppWindowMetrics.width, height: AppWindowMetrics.height)

        MenuBarExtra(Copy.text(.windowTitle, store.language), image: "MenuBarDog") {
            QuickAddMenu()
                .environmentObject(store)
                .environment(\.textScale, CGFloat(store.textSize.scale))
        }
        .menuBarExtraStyle(.window)
    }
}

enum AppWindowMetrics {
    static let width: CGFloat = 560
    static let height: CGFloat = 480
}

private struct UndoCommands: Commands {
    @ObservedObject var store: TaskStore

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            shortcutButton(store.undoMenuTitle, store: store, command: .undo, enabled: store.canUndo && !store.textFieldOwnsUndo) {
                store.undo()
            }
            shortcutButton(store.redoMenuTitle, store: store, command: .redo, enabled: store.canRedo && !store.textFieldOwnsUndo) {
                store.redo()
            }
        }
    }
}

private struct TaskCommands: Commands {
    @ObservedObject var store: TaskStore

    var body: some Commands {
        CommandMenu(Copy.text(.tasksMenu, store.language)) {
            shortcutButton(Copy.text(.newTask, store.language), store: store, command: .newTask, enabled: true) {
                store.requestNewTask()
            }

            Divider()

            shortcutButton(Copy.text(.selectPrevious, store.language), store: store, command: .selectPrevious, enabled: store.commandEnabled(.selectPrevious, when: !store.visibleOrder().isEmpty)) {
                store.moveSelection(by: -1)
            }
            shortcutButton(Copy.text(.selectNext, store.language), store: store, command: .selectNext, enabled: store.commandEnabled(.selectNext, when: !store.visibleOrder().isEmpty)) {
                store.moveSelection(by: 1)
            }
            shortcutButton(Copy.text(.selectAllTasks, store.language), store: store, command: .selectAllTasks, enabled: store.commandEnabled(.selectAllTasks, when: store.hasOpen)) {
                store.selectAllOpen()
            }
            shortcutButton(Copy.text(.clearSelection, store.language), store: store, command: .clearSelection, enabled: store.commandEnabled(.clearSelection, when: !store.selection.isEmpty)) {
                store.clearSelection()
            }

            Divider()

            shortcutButton(Copy.text(.toggleDone, store.language), store: store, command: .toggleDone, enabled: store.commandEnabled(.toggleDone, when: store.selectionIsToggleable)) {
                store.toggleSelectedCompletion()
            }
            shortcutButton(Copy.text(.rename, store.language), store: store, command: .rename, enabled: store.commandEnabled(.rename, when: store.selection.count == 1)) {
                store.requestRename()
            }
            shortcutButton(Copy.text(.moveUp, store.language), store: store, command: .moveUp, enabled: store.commandEnabled(.moveUp, when: store.selection.count == 1)) {
                store.nudgeSelection(upward: true)
            }
            shortcutButton(Copy.text(.moveDown, store.language), store: store, command: .moveDown, enabled: store.commandEnabled(.moveDown, when: store.selection.count == 1)) {
                store.nudgeSelection(upward: false)
            }

            Divider()

            shortcutButton(Copy.text(.deleteSelection, store.language), store: store, command: .deleteSelection, enabled: store.commandEnabled(.deleteSelection, when: !store.selection.isEmpty)) {
                store.deleteSelection()
            }
            shortcutButton(Copy.text(.clearCompleted, store.language), store: store, command: .clearCompleted, enabled: store.commandEnabled(.clearCompleted, when: store.hasCompleted)) {
                store.clearCompleted()
            }
        }
    }
}

@MainActor
@ViewBuilder
private func shortcutButton(
    _ title: String,
    store: TaskStore,
    command: AppCommand,
    enabled: Bool,
    action: @escaping () -> Void
) -> some View {
    if let binding = store.menuBinding(for: command, enabled: enabled), let key = binding.menuKey {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: binding.menuModifiers)
            .disabled(!enabled)
    } else {
        Button(title, action: action)
            .disabled(!enabled)
    }
}
