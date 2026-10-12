import SwiftUI
import NextUpShared

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var draftError: String?
    @State private var completedExpanded = false
    @State private var selectedID: UUID?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let loadError = store.loadError {
                    loadFailure(loadError)
                } else {
                    taskList
                }
            }
            .navigationTitle("接下来")
            .navigationSubtitle(navigationSubtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        composerFocused = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("新任务")
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.loadError != nil)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear {
            store.reload()
            composerFocused = store.document.items.isEmpty
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
        .onOpenURL { store.open(url: $0) }
        .alert("提示", isPresented: noticeIsPresented) {
            Button("好") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var navigationSubtitle: String {
        guard store.loadError == nil else { return "" }
        let count = TodoSorting.incompleteCount(store.document.items)
        return count == 0 ? "" : "\(count) 项"
    }

    private func manualOrder(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var taskList: some View {
        let topLevel = store.document.items.filter { $0.parentID == nil }
        let open = manualOrder(topLevel.filter { $0.status != .done || store.settlingIDs.contains($0.id) })
        let done = manualOrder(topLevel.filter { $0.status == .done && !store.settlingIDs.contains($0.id) })
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                composer
                ForEach(Array(open.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        taskDivider
                    }
                    TaskGroup(item: item, selectedID: $selectedID, siblingIDs: open.map(\.id))
                }
                if !done.isEmpty {
                    DisclosureGroup(isExpanded: $completedExpanded) {
                        ForEach(Array(done.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                taskDivider
                            }
                            TaskGroup(item: item, selectedID: $selectedID, siblingIDs: done.map(\.id))
                        }
                    } label: {
                        Text("已完成")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 22)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
    }

    private var taskDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
                TextField("新任务，可粘贴大纲", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .onSubmit(commitDraft)
                    .onChange(of: draft) { _, newValue in
                        guard OutlineParser.looksLikeOutline(newValue) else { return }
                        commitOutline(newValue)
                    }
            }
            .padding(.vertical, 12)
            if let draftError {
                Text(draftError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
        }
    }

    private func commitDraft() {
        let title = draft
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if OutlineParser.looksLikeOutline(title) || OutlineParser.parse(title, now: Date(), calendar: .current).count == 1 && title.contains("、") {
            commitOutline(title)
            return
        }
        commit {
            try store.add(title: title)
        }
    }

    private func commitOutline(_ text: String) {
        commit {
            try store.addOutline(text)
        }
    }

    private func commit(_ body: () throws -> Void) {
        do {
            try body()
            draft = ""
            draftError = nil
            composerFocused = true
        } catch let error as StoreError {
            draftError = error.message
        } catch {
            draftError = StoreError.writeFailed.message
        }
    }

    private func loadFailure(_ error: StoreError) -> some View {
        let canRestore = error == .corrupted && store.backupIsRestorable()
        return VStack(alignment: .leading, spacing: 8) {
            Text("暂时无法读取任务")
                .font(.title3.weight(.semibold))
            Text(error.message)
                .foregroundStyle(.secondary)
            if canRestore {
                Button("从最近的备份恢复") { store.restoreBackup() }
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(36)
    }

    private var noticeIsPresented: Binding<Bool> {
        Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    }
}

private struct TaskGroup: View {
    @EnvironmentObject private var store: TaskStore
    let item: TodoItem
    @Binding var selectedID: UUID?
    var siblingIDs: [UUID] = []
    var depth: Int = 0
    @State private var composingChild = false
    @State private var childTitle = ""
    @FocusState private var childFocused: Bool

    private var children: [TodoItem] {
        store.document.items
            .filter { $0.parentID == item.id }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ElasticTaskRow(
                item: item,
                depth: depth,
                siblingIDs: siblingIDs,
                isSelected: selectedID == item.id,
                canSelect: depth < 2
            ) {
                guard depth < 2 else { return }
                if selectedID == item.id {
                    selectedID = nil
                    composingChild = false
                    childTitle = ""
                } else {
                    selectedID = item.id
                }
            }
            ForEach(children) { child in
                TaskGroup(item: child, selectedID: $selectedID, siblingIDs: children.map(\.id), depth: depth + 1)
            }
            if depth < 2, selectedID == item.id {
                if composingChild {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22)
                        TextField("子条目", text: $childTitle)
                            .textFieldStyle(.plain)
                            .focused($childFocused)
                            .onSubmit(commitChild)
                    }
                    .padding(.leading, CGFloat(depth + 1) * 34)
                    .padding(.vertical, 6)
                } else {
                    Button {
                        composingChild = true
                        childFocused = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("添加")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .nextUpClickable(cornerRadius: 8, horizontalPadding: 6)
                    .padding(.leading, CGFloat(depth + 1) * 34 + 34)
                    .padding(.vertical, 4)
                    .accessibilityLabel("添加子条目")
                }
            }
        }
        .onChange(of: selectedID) { _, newValue in
            guard newValue != item.id else { return }
            composingChild = false
            childTitle = ""
        }
    }

    private func commitChild() {
        let title = childTitle
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            composingChild = false
            return
        }
        do {
            try store.add(title: title, parentID: item.id)
            childTitle = ""
            childFocused = true
        } catch {
            composingChild = false
        }
    }
}

private struct ElasticTaskRow: View {
    private enum PointerMode {
        case idle
        case charging
        case swiping
        case armed
    }

    @EnvironmentObject private var store: TaskStore
    let item: TodoItem
    var depth: Int = 0
    var siblingIDs: [UUID] = []
    var isSelected = false
    var canSelect = false
    var onSelect: () -> Void = {}
    @State private var offset: CGFloat = 0
    @State private var vertical: CGFloat = 0
    @State private var charge: CGFloat = 0
    @State private var mode: PointerMode = .idle
    @State private var chargeTask: Task<Void, Never>?
    @State private var suppressTap = false
    @State private var rowHeight: CGFloat = 44
    @State private var editing = false
    @State private var editTitle = ""
    @State private var parentCheckScale: CGFloat = 1
    @FocusState private var editFocused: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                Text("删除")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red.opacity(min(1, Double(max(0, -offset)) / 72)))

            HStack(spacing: 12) {
                if !hasChildren {
                    Button(action: toggle) {
                        Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(item.status == .done ? Color.secondary : Color.primary)
                            .frame(width: 28, height: 28)
                            .nextUpClickableCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.status == .done ? "重新打开：\(item.title)" : "完成：\(item.title)")
                } else if item.status == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .scaleEffect(parentCheckScale)
                        .accessibilityLabel("已完成：\(item.title)")
                } else {
                    Color.clear
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }

                titleControl
            }
            .padding(.vertical, 8)
            .padding(.leading, CGFloat(depth) * 34)
            .background(rowBackground)
            .background { if needsPlate { Rectangle().fill(.background) } }
            .overlay(alignment: .bottom) { chargeBar }
            .scaleEffect(mode == .armed ? 1.02 : 1)
            .shadow(color: mode == .armed ? Color.black.opacity(0.12) : .clear, radius: mode == .armed ? 8 : 0, y: mode == .armed ? 3 : 0)
            .offset(x: offset, y: mode == .armed ? vertical : 0)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: RowHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(RowHeightKey.self) { rowHeight = $0 }
            .simultaneousGesture(pointer)
        }
        .modifier(RowClip(enabled: mode != .armed))
        .zIndex(mode == .armed ? 1 : 0)
        .contextMenu {
            Button("编辑") { beginEditing() }
            Button("删除", role: .destructive) { store.delete(id: item.id) }
        }
        .accessibilityElement(children: .contain)
        .onDisappear { cancelCharge() }
        .onChange(of: editing) { _, isEditing in
            if isEditing {
                DispatchQueue.main.async { editFocused = true }
            }
        }
        .onChange(of: item.status) { old, new in
            guard hasChildren, old != .done, new == .done else { return }
            parentCheckScale = 0.82
            withAnimation(.easeOut(duration: 0.22)) { parentCheckScale = 1 }
        }
    }

    @ViewBuilder
    private var chargeBar: some View {
        if mode == .charging, charge > 0 {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .scaleEffect(x: charge, y: 1, anchor: .leading)
        }
    }

    @ViewBuilder
    private var titleControl: some View {
        let label = HStack(spacing: 12) {
            if editing {
                TextField("标题", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($editFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand { editing = false }
            } else {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(item.status == .done ? .secondary : .primary)
                    .strikethrough(item.status == .done, color: .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if item.status != .done, let text = trailing {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(isOverdue ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        if canSelect, !editing {
            label
                .nextUpClickable(cornerRadius: 8, horizontalPadding: 0, showsHoverFill: !isSelected)
                .onTapGesture {
                    if suppressTap {
                        suppressTap = false
                        return
                    }
                    onSelect()
                }
        } else {
            label
        }
    }

    private var needsPlate: Bool {
        offset != 0 || mode == .armed || mode == .swiping
    }

    private var rowBackground: Color {
        if store.highlightedID == item.id { return Color.accentColor.opacity(0.12) }
        if isSelected { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var trailing: String? {
        let auxiliary = TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, now: Date(), calendar: .current)
        return auxiliary.text
    }

    private var isOverdue: Bool {
        TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, now: Date(), calendar: .current).emphasis == .overdue
    }

    private var hasChildren: Bool {
        store.document.items.contains { $0.parentID == item.id }
    }

    private func toggle() {
        store.setStatus(id: item.id, status: item.status == .done ? .todo : .done)
    }

    private func beginEditing() {
        editTitle = item.title
        editing = true
    }

    private func commitEdit() {
        if store.rename(id: item.id, title: editTitle) {
            editing = false
        }
    }

    private var pointer: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !editing else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                switch mode {
                case .armed:
                    vertical = dy
                    suppressTap = true
                case .swiping:
                    offset = rubberBand(dx)
                    suppressTap = true
                case .idle, .charging:
                    if abs(dx) > 16, abs(dx) > abs(dy) + 8 {
                        cancelCharge()
                        mode = .swiping
                        offset = rubberBand(dx)
                        suppressTap = true
                    } else if mode == .idle {
                        beginCharge()
                    }
                }
            }
            .onEnded { value in
                let ignoreTap = charge > 0.25 || mode == .armed || mode == .swiping
                if mode == .armed {
                    commitLift(value.translation.height)
                } else if mode == .swiping && value.translation.width < -88 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        offset = -720
                    }
                    let id = item.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        store.delete(id: id)
                    }
                } else {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.56)) {
                        offset = 0
                    }
                }
                cancelCharge()
                mode = .idle
                vertical = 0
                if ignoreTap {
                    suppressTap = true
                    DispatchQueue.main.async { suppressTap = false }
                }
            }
    }

    private func beginCharge() {
        guard chargeTask == nil else { return }
        mode = .charging
        let start = Date()
        chargeTask = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= 2 {
                    guard !Task.isCancelled else { return }
                    charge = 1
                    withAnimation(.easeOut(duration: 0.16)) {
                        mode = .armed
                    }
                    return
                }
                charge = CGFloat(elapsed / 2)
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func cancelCharge() {
        chargeTask?.cancel()
        chargeTask = nil
        charge = 0
    }

    private func commitLift(_ translation: CGFloat) {
        let height = max(rowHeight, 36)
        let delta = Int((translation / height).rounded())
        guard delta != 0, let index = siblingIDs.firstIndex(of: item.id) else { return }
        let target = min(max(index + delta, 0), siblingIDs.count - 1)
        guard target != index else { return }
        let before: UUID?
        if target > index {
            let next = target + 1
            before = next < siblingIDs.count ? siblingIDs[next] : nil
        } else {
            before = siblingIDs[target]
        }
        store.move(id: item.id, before: before)
    }

    private func rubberBand(_ translation: CGFloat) -> CGFloat {
        if translation >= 0 { return translation * 0.12 }
        let travel = -translation
        if travel <= 120 { return -travel }
        return -(120 + (travel - 120) * 0.22)
    }
}

private struct RowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 44
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RowClip: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.clipped()
        } else {
            content
        }
    }
}

extension View {
    func nextUpClickable(cornerRadius: CGFloat = 8, horizontalPadding: CGFloat = 6, showsHoverFill: Bool = true) -> some View {
        modifier(NextUpClickableStyle(kind: .rounded(cornerRadius), horizontalPadding: horizontalPadding, showsHoverFill: showsHoverFill))
    }

    func nextUpClickableCircle() -> some View {
        modifier(NextUpClickableStyle(kind: .circle, horizontalPadding: 0))
    }
}

private struct NextUpClickableStyle: ViewModifier {
    enum Kind {
        case rounded(CGFloat)
        case circle
    }

    var kind: Kind
    var horizontalPadding: CGFloat
    var showsHoverFill = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        switch kind {
        case .rounded(let radius):
            styled(content, shape: RoundedRectangle(cornerRadius: radius, style: .continuous), verticalPadding: 2)
        case .circle:
            styled(content, shape: Circle(), verticalPadding: 0)
        }
    }

    private func styled<S: Shape>(_ content: Content, shape: S, verticalPadding: CGFloat) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                shape
                    .fill(Color.primary.opacity(0.045))
                    .opacity(showsHoverFill && hovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: hovering)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .onContinuousHover { phase in
                let inside = if case .active = phase { true } else { false }
                if hovering != inside { hovering = inside }
            }
            .pointerStyle(.link)
    }
}
