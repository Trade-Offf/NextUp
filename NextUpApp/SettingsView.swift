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
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                settingsRow(Copy.text(.language, store.language)) {
                    Picker(Copy.text(.language, store.language), selection: language) {
                        ForEach(AppLanguage.allCases, id: \.self) { item in
                            Text(item.nativeName).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                settingsRow(Copy.text(.shortcuts, store.language)) {
                    Button(Copy.text(.customizeShortcuts, store.language)) {
                        showsShortcuts = true
                    }
                    .buttonStyle(.bordered)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            SettingsCard {
                settingsRow(Copy.text(.textSize, store.language)) {
                    Picker(Copy.text(.textSize, store.language), selection: textSize) {
                        ForEach(TextSize.allCases, id: \.self) { size in
                            Text(textSizeName(size)).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                settingsRow(Copy.text(.showWidgetBadge, store.language)) {
                    Toggle(Copy.text(.showWidgetBadge, store.language), isOn: showsBadge)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsCard {
                settingsRow(Copy.text(.dataSection, store.language)) {
                    HStack(spacing: 8) {
                        Button(Copy.text(.clearToday, store.language)) {
                            pendingClear = .writtenToday
                        }
                        .buttonStyle(.bordered)
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            SettingsWindowSizer()
        }
        .background {
            NextUpRoundedSheet(isPresented: $showsShortcuts) {
                ShortcutSettings {
                    showsShortcuts = false
                }
                .environmentObject(store)
            }
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

    private var textSize: Binding<TextSize> {
        Binding(get: { store.textSize }, set: { store.selectTextSize($0) })
    }

    private func textSizeName(_ size: TextSize) -> String {
        switch size {
        case .small: return Copy.text(.textSizeSmall, store.language)
        case .medium: return Copy.text(.textSizeMedium, store.language)
        case .large: return Copy.text(.textSizeLarge, store.language)
        }
    }

    private var showsBadge: Binding<Bool> {
        Binding(
            get: { store.showsWidgetBadge },
            set: { store.setShowsWidgetBadge($0) }
        )
    }

    private func settingsRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

private struct SettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: NextUpChrome.containerRadius, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        }
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
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ShortcutGroup.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(groupTitle(group))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 12)
                            SettingsCard {
                                ForEach(group.commands, id: \.self) { command in
                                    ShortcutRow(command: command)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                    if command != group.commands.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

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
                .buttonStyle(.bordered)
                Spacer()
                Button(Copy.text(.shortcutDone, store.language)) {
                    store.cancelRecording()
                    onDone()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .frame(width: 440, height: 340)
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
            HStack(spacing: 12) {
                Text(Copy.shortcutTitle(command, store.language))
                Spacer(minLength: 12)
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

/// 系统 sheet 的圆角在 macOS 26 上收不住，浮层改成自己画的圆角卡片。
struct NextUpRoundedSheet<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var content: Content

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onWindow = { [weak coordinator = context.coordinator] in
            coordinator?.syncIfNeeded()
        }
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        context.coordinator.isPresented = isPresented
        context.coordinator.content = AnyView(content)
        context.coordinator.dismiss = { isPresented = false }
        context.coordinator.anchor = view
        context.coordinator.syncIfNeeded()
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator {
        var isPresented = false
        var content = AnyView(EmptyView())
        var dismiss: () -> Void = {}
        weak var anchor: AnchorView?
        private var panel: RoundedSheetPanel?
        private var model: SheetModel?
        private var observers: [NSObjectProtocol] = []

        func syncIfNeeded() {
            guard let anchor else { return }
            if !isPresented {
                close()
                return
            }
            guard let parent = anchor.window, parent.frame.width > 1, parent.frame.height > 1 else { return }
            if panel == nil || panel?.parent !== parent {
                close()
                open(parent: parent)
            }
            guard let panel, let model else { return }
            let size = parent.frame.size
            if model.size != size {
                model.size = size
            }
            if panel.frame != parent.frame {
                panel.setFrame(parent.frame, display: true)
            }
        }

        private func open(parent: NSWindow) {
            let model = SheetModel(content: content, size: parent.frame.size, dismiss: { [weak self] in
                self?.dismiss()
            })
            let host = NSHostingView(rootView: SheetRoot(model: model))
            host.safeAreaRegions = []
            let panel = RoundedSheetPanel(
                contentRect: parent.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.isMovable = false
            panel.contentView = host
            host.frame = NSRect(origin: .zero, size: parent.frame.size)
            host.autoresizingMask = [.width, .height]
            parent.addChildWindow(panel, ordered: .above)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
            self.panel = panel
            self.model = model
            let move = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncIfNeeded() }
            }
            let resize = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncIfNeeded() }
            }
            let key = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.panel?.orderFront(nil) }
            }
            observers = [move, resize, key]
        }

        func close() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            panel = nil
            model = nil
        }
    }

    final class AnchorView: NSView {
        var onWindow: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?()
        }
    }
}

private final class SheetModel: ObservableObject {
    @Published var content: AnyView
    @Published var size: CGSize
    var dismiss: () -> Void

    init(content: AnyView, size: CGSize, dismiss: @escaping () -> Void) {
        self.content = content
        self.size = size
        self.dismiss = dismiss
    }
}

private struct SheetRoot: View {
    @ObservedObject var model: SheetModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture { model.dismiss() }
            model.content
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: NextUpChrome.containerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                .padding(.top, 72)
                .padding(.bottom, 24)
        }
        .frame(width: model.size.width, height: model.size.height)
    }
}

private final class RoundedSheetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
