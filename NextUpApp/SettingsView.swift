import SwiftUI
import NextUpShared

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label(Copy.text(.general, store.language), systemImage: "gearshape")
                }
        }
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        Form {
            Picker(Copy.text(.language, store.language), selection: language) {
                ForEach(AppLanguage.allCases, id: \.self) { item in
                    Text(item.nativeName).tag(item)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }

    private var language: Binding<AppLanguage> {
        Binding(
            get: { store.language },
            set: { newValue in
                guard newValue != store.language else { return }
                store.selectLanguage(newValue)
            }
        )
    }
}
