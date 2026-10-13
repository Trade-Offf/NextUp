import SwiftUI
import NextUpShared

@main
struct NextUpApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 560, height: 480)

        Settings {
            SettingsView()
                .environmentObject(store)
        }

        MenuBarExtra(Copy.text(.windowTitle, store.language), systemImage: "checklist") {
            QuickAddMenu()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
