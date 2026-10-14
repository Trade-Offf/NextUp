import AppKit
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
    @State private var showsShortcuts = false

    var body: some View {
        Form {
            Picker(Copy.text(.language, store.language), selection: language) {
                ForEach(AppLanguage.allCases, id: \.self) { item in
                    Text(item.nativeName).tag(item)
                }
            }
            .pickerStyle(.radioGroup)

            LabeledContent(Copy.text(.shortcuts, store.language)) {
                Button(Copy.text(.customizeShortcuts, store.language)) {
                    showsShortcuts = true
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            LabeledContent(Copy.text(.dataSection, store.language)) {
                HStack(spacing: 8) {
                    Button(Copy.text(.clearToday, store.language)) {
                        pendingClear = .writtenToday
                    }
                    .disabled(store.clearCount(.writtenToday) == 0)

                    ClearAllButton(
                        title: Copy.text(.clearHistory, store.language),
                        isEnabled: store.clearCount(.everything) > 0
                    ) {
                        pendingClear = .everything
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            SettingsWindowSizer()
        }
        .sheet(isPresented: $showsShortcuts) {
            ShortcutSettings()
                .environmentObject(store)
        }
        .confirmationDialog(
            pendingClear.map { Copy.clearConfirmTitle($0, store.language) } ?? "",
            isPresented: clearDialogPresented,
            titleVisibility: .visible
        ) {
            if pendingClear == .everything {
                Button(confirmButtonTitle, role: .destructive) {
                    if let pendingClear {
                        store.clear(pendingClear)
                    }
                }
            } else {
                Button(confirmButtonTitle) {
                    if let pendingClear {
                        store.clear(pendingClear)
                    }
                }
            }
            Button(Copy.text(.cancel, store.language), role: .cancel) {}
        } message: {
            if let pendingClear {
                Text(Copy.clearWarning(pendingClear, store.clearCount(pendingClear), store.language))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @State private var pendingClear: TodoClearing.Scope?

    private var confirmButtonTitle: String {
        switch pendingClear {
        case .writtenToday: return Copy.text(.clearToday, store.language)
        case .everything: return Copy.text(.clearHistory, store.language)
        case nil: return ""
        }
    }

    private var clearDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingClear != nil },
            set: { isPresented in
                if !isPresented { pendingClear = nil }
            }
        )
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

private struct ClearAllButton: NSViewRepresentable {
    var title: String
    var isEnabled: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setButtonType(.momentaryPushIn)
        configure(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        configure(button, context: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        nsView.sizeToFit()
        return nsView.fittingSize
    }

    private func configure(_ button: NSButton, context: Context) {
        button.isEnabled = isEnabled
        let color: NSColor = isEnabled ? .systemRed : .disabledControlTextColor
        button.contentTintColor = isEnabled ? .systemRed : nil
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: color
            ]
        )
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func press() {
            action()
        }
    }
}

private struct SettingsWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let target = NSSize(width: AppWindowMetrics.width, height: AppWindowMetrics.height)
            if window.attachedSheet != nil {
                window.contentMinSize = NSSize(width: 480, height: 360)
                window.contentMaxSize = NSSize(width: 900, height: 900)
                return
            }
            let content = window.contentRect(forFrameRect: NSRect(origin: .zero, size: target)).size
            window.contentMinSize = content
            window.contentMaxSize = content
            guard abs(window.frame.width - target.width) > 0.5 || abs(window.frame.height - target.height) > 0.5 else { return }
            var frame = window.frame
            frame.origin.y += frame.height - target.height
            frame.size = target
            window.setFrame(frame, display: true)
        }
    }
}

private struct ShortcutSettings: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(ShortcutGroup.allCases, id: \.self) { group in
                    Section(groupTitle(group)) {
                        ForEach(group.commands, id: \.self) { command in
                            ShortcutRow(command: command)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let shortcutError = store.shortcutError {
                Text(shortcutError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            HStack {
                Button(Copy.text(.restoreDefaults, store.language)) {
                    store.resetShortcuts()
                }
                Spacer()
                Button(Copy.text(.shortcutDone, store.language)) {
                    dismiss()
                }
            }
            .padding(20)
        }
        .frame(width: 480)
        .onDisappear { store.cancelRecording() }
    }

    private func groupTitle(_ group: ShortcutGroup) -> String {
        switch group {
        case .edit:
            return Copy.text(.shortcutGroupEdit, store.language)
        case .tasks:
            return Copy.text(.tasksMenu, store.language)
        }
    }
}

private struct ShortcutRow: View {
    @EnvironmentObject private var store: TaskStore
    let command: AppCommand

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            LabeledContent(Copy.shortcutTitle(command, store.language)) {
                Button(capsuleTitle) {
                    store.beginRecording(command)
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 88)
            }
            if store.recordingCommand == command {
                recordingNote
            }
        }
    }

    private var capsuleTitle: String {
        if store.recordingCommand == command {
            if case .conflict(_, let binding) = store.recordingNote {
                return binding.display
            }
            return Copy.text(.pressShortcut, store.language)
        }
        if let binding = store.shortcuts.binding(for: command) {
            return binding.display
        }
        return Copy.text(.noShortcut, store.language)
    }

    @ViewBuilder
    private var recordingNote: some View {
        switch store.recordingNote {
        case .reserved:
            Text(Copy.text(.shortcutReserved, store.language))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .conflict(let other, _):
            HStack(spacing: 8) {
                Text(Copy.shortcutUsedBy(Copy.shortcutTitle(other, store.language), store.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(Copy.text(.shortcutReplace, store.language)) {
                    store.confirmReplacement()
                }
                .buttonStyle(.borderless)
            }
        case nil:
            EmptyView()
        }
    }
}
