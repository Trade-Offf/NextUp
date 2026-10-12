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

        MenuBarExtra("Next Up", systemImage: "checklist") {
            QuickAddMenu()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
