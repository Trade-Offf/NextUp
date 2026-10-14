import AppKit
import SwiftUI
import NextUpShared

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager
    @State private var draft = ""
    @State private var draftError: StoreError?
    @State private var pendingPasteCount: Int?
    @State private var listMotionReady = false
    @FocusState private var composerFocused: Bool
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = prepareComposerReturn()
        NavigationStack {
            Group {
                if let loadError = store.loadError {
                    loadFailure(loadError)
                } else {
                    taskList
                }
            }
            .navigationTitle(Copy.text(.windowTitle, store.language))
            .navigationSubtitle(navigationSubtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help(Copy.text(.settings, store.language))
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background {
            NextUpAluminumFill(window: true)
                .ignoresSafeArea()
        }
        .toolbarBackground(Color.clear, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .background(KeyWindowProbe { window, isKey in
            store.setWindow(window, isKey: isKey)
        })
        .onAppear {
            store.undoManager = undoManager
            store.observeUndoStack()
            store.reload()
            composerFocused = store.document.items.isEmpty
            DispatchQueue.main.async { listMotionReady = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.undoManager = undoManager
                store.observeUndoStack()
                store.reload()
            }
        }
        .onChange(of: store.focusComposerToken) { _, _ in
            composerFocused = true
        }
        .onChange(of: composerFocused) { _, focused in
            store.setTyping("composer", active: focused)
            store.setFieldOwnsUndo("composer", active: focused && !draft.isEmpty)
        }
        .onDisappear {
            store.setTyping("composer", active: false)
            store.setFieldOwnsUndo("composer", active: false)
        }
        .onOpenURL { store.open(url: $0) }
        .alert(Copy.text(.notice, store.language), isPresented: noticeIsPresented) {
            Button(Copy.text(.ok, store.language)) { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var navigationSubtitle: String {
        guard store.loadError == nil else { return "" }
        let count = TodoSorting.incompleteCount(store.document.items)
        return count == 0 ? "" : Copy.openCount(count, store.language)
    }

    private func manualOrder(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var listAnimation: Animation? {
        guard listMotionReady, store.animatesListChanges else { return nil }
        return NextUpChrome.resolved(NextUpChrome.settle, reduceMotion: reduceMotion)
    }

    private var taskList: some View {
        let topLevel = store.document.items.filter { $0.parentID == nil }
        let open = manualOrder(topLevel.filter { $0.status != .done || store.settlingIDs.contains($0.id) })
        let done = manualOrder(topLevel.filter { $0.status == .done && !store.settlingIDs.contains($0.id) })
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    composer
                    SiblingColumn(items: open, depth: 0, dividers: true)
                    if !done.isEmpty {
                        DisclosureGroup(isExpanded: showsCompleted) {
                            SiblingColumn(items: done, depth: 0, dividers: true, fadesRemoval: true)
                        } label: {
                            Text(Copy.text(.completed, store.language))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture { store.showsCompleted.toggle() }
                                .pointerStyle(.link)
                        }
                        .contextMenu {
                            Button(Copy.text(.clearCompleted, store.language)) {
                                store.clearCompleted()
                            }
                            .disabled(!store.hasCompleted)
                        }
                        .padding(.top, 22)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(listAnimation, value: open.map(\.id))
                .animation(listAnimation, value: done.map(\.id))
                .animation(listAnimation, value: store.document.items.map(\.id))
            }
            .scrollIndicators(.automatic)
            .onChange(of: store.selectionScrollID) { _, id in
                guard let id else { return }
                if reduceMotion {
                    proxy.scrollTo(id, anchor: .center)
                } else {
                    withAnimation(NextUpChrome.settle) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var showsCompleted: Binding<Bool> {
        Binding(get: { store.showsCompleted }, set: { store.showsCompleted = $0 })
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
                TextField(Copy.text(.composerPlaceholder, store.language), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: NextUpChrome.taskSize))
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .onSubmit(commitDraft)
                    .onExitCommand(perform: clearDraft)
                    .onChange(of: draft) { _, newValue in
                        store.setFieldOwnsUndo("composer", active: composerFocused && !newValue.isEmpty)
                        guard !store.isApplyingUndo else { return }
                        let count = OutlineParser.entryCount(newValue)
                        if count > OutlineParser.pasteConfirmLimit {
                            pendingPasteCount = count
                            return
                        }
                        pendingPasteCount = nil
                        guard OutlineParser.looksLikeOutline(newValue) else { return }
                        commitOutline(newValue)
                    }
            }
            .padding(.vertical, 12)
            if let pendingPasteCount {
                HStack(spacing: 8) {
                    Text(Copy.pendingPaste(pendingPasteCount, store.language))
                        .font(.subheadline.weight(.medium))
                    Text(Copy.text(.pasteHint, store.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                .transition(pendingTransition)
            }
            if let draftError {
                Text(draftError.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
        }
        .animation(NextUpChrome.resolved(NextUpChrome.settle, reduceMotion: reduceMotion), value: pendingPasteCount != nil)
    }

    private var pendingTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -4)),
            removal: .opacity
        )
    }

    private func clearDraft() {
        let hasDraft = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingPasteCount != nil
        draft = ""
        draftError = nil
        pendingPasteCount = nil
        guard !hasDraft else { return }
        composerFocused = false
        store.clearSelection()
    }

    private func prepareComposerReturn() {
        store.composerReturn = composerFocused ? { commitDraft() } : nil
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
        let pending = pendingPasteCount
        pendingPasteCount = nil
        commit {
            try store.addOutline(text)
        }
        if draftError != nil { pendingPasteCount = pending }
    }

    private func commit(_ body: () throws -> Void) {
        do {
            try body()
            store.performWithoutUndo {
                draft = ""
                draftError = nil
                composerFocused = true
            }
        } catch let error as StoreError {
            draftError = error
        } catch {
            draftError = .writeFailed
        }
    }

    private func loadFailure(_ error: StoreError) -> some View {
        let canRestore = error == .corrupted && store.backupIsRestorable()
        return VStack(alignment: .leading, spacing: 8) {
            Text(Copy.text(.readFailed, store.language))
                .font(.title3.weight(.semibold))
            Text(error.message)
                .foregroundStyle(.secondary)
            if canRestore {
                Button(Copy.text(.restoreBackup, store.language)) { store.restoreBackup() }
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

private struct SiblingColumn: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [TodoItem]
    var depth: Int
    var dividers: Bool
    var fadesRemoval = false
    @State private var drag: DragState?
    @State private var dragGeneration = 0
    @State private var heights: [UUID: CGFloat] = [:]

    private struct DragState {
        var id: UUID
        var origin: Int
        var translation: CGFloat
        var slot: Int
    }

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            VStack(alignment: .leading, spacing: 0) {
                if dividers, index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(NextUpChrome.hairlineOpacity))
                        .frame(height: NextUpChrome.hairline)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                TaskGroup(
                    item: item,
                    depth: depth,
                    onDrag: { translation in
                        updateDrag(id: item.id, index: index, translation: translation)
                    },
                    onDragEnd: { endDrag(id: item.id) }
                )
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: CellHeightKey.self, value: [item.id: proxy.size.height])
                }
            }
            .background {
                if isLifted(item.id) {
                    Rectangle().fill(.background)
                }
            }
            .scaleEffect(isLifted(item.id) && !reduceMotion ? NextUpChrome.liftScale : 1)
            .shadow(
                color: isLifted(item.id) ? Color.black.opacity(0.12) : .clear,
                radius: isLifted(item.id) ? 8 : 0,
                y: isLifted(item.id) ? 3 : 0
            )
            .animation(NextUpChrome.resolved(NextUpChrome.lift, reduceMotion: reduceMotion), value: isLifted(item.id))
            .offset(y: shift(for: item.id, index: index))
            .animation(
                isLifted(item.id) ? nil : NextUpChrome.resolved(NextUpChrome.settle, reduceMotion: reduceMotion),
                value: shift(for: item.id, index: index)
            )
            .zIndex(isLifted(item.id) ? 1 : 0)
            .id(item.id)
            .transition(
                .asymmetric(
                    insertion: .opacity,
                    removal: fadesRemoval || store.fadesRowRemoval || reduceMotion
                        ? .opacity
                        : .move(edge: .leading).combined(with: .opacity)
                )
            )
        }
        .onPreferenceChange(CellHeightKey.self) { heights = $0 }
    }

    private func isLifted(_ id: UUID) -> Bool {
        drag?.id == id
    }

    private func shift(for id: UUID, index: Int) -> CGFloat {
        guard let drag else { return 0 }
        if drag.id == id { return drag.translation }
        let span = height(of: drag.id)
        if drag.slot > drag.origin, index > drag.origin, index <= drag.slot {
            return -span
        }
        if drag.slot < drag.origin, index >= drag.slot, index < drag.origin {
            return span
        }
        return 0
    }

    private func updateDrag(id: UUID, index: Int, translation: CGFloat) {
        guard items.count > 1 else { return }
        dragGeneration += 1
        let origin = drag?.id == id ? drag!.origin : index
        let slot = slotIndex(origin: origin, translation: translation)
        drag = DragState(id: id, origin: origin, translation: translation, slot: slot)
    }

    private func endDrag(id: UUID) {
        guard let drag, drag.id == id else { return }
        guard drag.slot != drag.origin else {
            NextUpChrome.perform(NextUpChrome.settle, reduceMotion: reduceMotion) {
                self.drag = nil
            }
            return
        }
        let before = beforeID(origin: drag.origin, slot: drag.slot)
        let landing = landingDistance(origin: drag.origin, slot: drag.slot)
        let generation = dragGeneration
        if reduceMotion {
            store.move(id: id, before: before)
            self.drag = nil
            return
        }
        var settled = drag
        settled.translation = landing
        withAnimation(NextUpChrome.settle) { self.drag = settled }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            guard dragGeneration == generation, self.drag?.id == id else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.move(id: id, before: before)
                self.drag = nil
            }
        }
    }

    private func slotIndex(origin: Int, translation: CGFloat) -> Int {
        var index = origin
        var remaining = translation
        if remaining > 0 {
            while index < items.count - 1 {
                let next = height(of: items[index + 1].id)
                if remaining < next / 2 { break }
                remaining -= next
                index += 1
            }
        } else if remaining < 0 {
            while index > 0 {
                let previous = height(of: items[index - 1].id)
                if -remaining < previous / 2 { break }
                remaining += previous
                index -= 1
            }
        }
        return index
    }

    private func landingDistance(origin: Int, slot: Int) -> CGFloat {
        if slot > origin {
            return (origin + 1...slot).reduce(0) { $0 + height(of: items[$1].id) }
        }
        if slot < origin {
            return -((slot..<origin).reduce(0) { $0 + height(of: items[$1].id) })
        }
        return 0
    }

    private func beforeID(origin: Int, slot: Int) -> UUID? {
        if slot > origin {
            return slot + 1 < items.count ? items[slot + 1].id : nil
        }
        return items[slot].id
    }

    private func height(of id: UUID) -> CGFloat {
        max(heights[id] ?? 44, 36)
    }
}

private struct CellHeightKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TaskGroup: View {
    @EnvironmentObject private var store: TaskStore
    let item: TodoItem
    var depth: Int = 0
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnd: () -> Void = {}
    @State private var composingChild = false
    @State private var childTitle = ""
    @FocusState private var childFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                isSelected: store.selection.contains(item.id),
                canSelect: true,
                onSelect: { select(item.id) },
                onDrag: onDrag,
                onDragEnd: onDragEnd
            )
            SiblingColumn(items: children, depth: depth + 1, dividers: false)
            Group {
                if depth < 2, store.selection == [item.id] {
                    addComposer
                        .transition(addTransition)
                }
            }
            .animation(addPresenceAnimation, value: store.selection == [item.id])
        }
        .onChange(of: store.selection) { _, newValue in
            guard newValue != [item.id] else { return }
            composingChild = false
            childTitle = ""
            store.setTyping("child-\(item.id)", active: false)
            store.setFieldOwnsUndo("child-\(item.id)", active: false)
        }
        .onDisappear {
            store.setFieldOwnsUndo("child-\(item.id)", active: false)
        }
    }

    private func select(_ id: UUID) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
            store.toggleSelection(id)
        } else if flags.contains(.shift) {
            store.selectRange(to: id)
        } else {
            store.selectOnly(id)
        }
    }

    private var showsAdd: Bool { store.selection == [item.id] }

    private var addPresenceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return showsAdd ? NextUpChrome.settle.delay(0.05) : .easeOut(duration: 0.14)
    }

    private var addTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -4)),
            removal: .opacity
        )
    }

    private var addComposer: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .onTapGesture(perform: beginComposingChild)
            Group {
                if composingChild {
                    TextField(Copy.text(.subtask, store.language), text: $childTitle)
                        .textFieldStyle(.plain)
                        .focused($childFocused)
                        .onSubmit(commitChild)
                        .onExitCommand(perform: cancelComposingChild)
                        .onChange(of: childFocused) { _, focused in
                            store.setTyping("child-\(item.id)", active: focused)
                            store.setFieldOwnsUndo("child-\(item.id)", active: focused && !childTitle.isEmpty)
                        }
                        .onChange(of: childTitle) { _, value in
                            store.setFieldOwnsUndo("child-\(item.id)", active: childFocused && !value.isEmpty)
                        }
                } else {
                    Text(Copy.text(.add, store.language))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginComposingChild)
                }
            }
            .animation(NextUpChrome.resolved(NextUpChrome.press, reduceMotion: reduceMotion), value: composingChild)
        }
        .font(.system(size: NextUpChrome.taskSize))
        .padding(.leading, CGFloat(depth + 1) * NextUpChrome.windowIndent)
        .padding(.vertical, NextUpChrome.windowRowPadding)
        .nextUpClickable(cornerRadius: 8, horizontalPadding: 0, showsHoverFill: !composingChild)
        .accessibilityLabel(Copy.text(.addSubtask, store.language))
    }

    private func beginComposingChild() {
        guard !composingChild else { return }
        composingChild = true
        childFocused = true
    }

    private func cancelComposingChild() {
        childTitle = ""
        composingChild = false
        store.setTyping("child-\(item.id)", active: false)
        store.setFieldOwnsUndo("child-\(item.id)", active: false)
    }

    private func commitChild() {
        let title = childTitle
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancelComposingChild()
            return
        }
        do {
            try store.add(title: title, parentID: item.id)
            store.performWithoutUndo { childTitle = "" }
            childFocused = true
        } catch let error as StoreError {
            store.notice = error.message
        } catch {
            store.notice = StoreError.writeFailed.message
        }
    }
}

private struct ElasticTaskRow: View {
    @EnvironmentObject private var store: TaskStore
    let item: TodoItem
    var depth: Int = 0
    var isSelected = false
    var canSelect = false
    var onSelect: () -> Void = {}
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnd: () -> Void = {}
    @State private var suppressTap = false
    @State private var editing = false
    @State private var editTitle = ""
    @State private var parentCheckScale: CGFloat = 1
    @FocusState private var editFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            if !hasChildren {
                Button(action: toggle) {
                    statusSymbol
                        .nextUpClickableCircle()
                }
                .buttonStyle(NextUpCircleButtonStyle())
                .accessibilityLabel(item.status == .done ? Copy.reopen(item.title, store.language) : Copy.complete(item.title, store.language))
            } else if item.status == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .scaleEffect(parentCheckScale)
                    .accessibilityLabel(Copy.completedItem(item.title, store.language))
            }

            titleControl
        }
        .padding(.vertical, NextUpChrome.windowRowPadding)
        .padding(.leading, CGFloat(depth) * NextUpChrome.windowIndent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                selectionPlate(color: Color.primary.opacity(0.05), active: isSelected)
                selectionPlate(color: Color.accentColor.opacity(0.12), active: store.highlightedID == item.id)
            }
        }
        .simultaneousGesture(editing ? nil : pointer)
        .contextMenu {
            Button(Copy.text(.edit, store.language)) { beginEditing() }
            Button(deleteLabel, role: .destructive) {
                let ids = deletionIDs
                let run = { store.delete(ids: ids) }
                if ids.count > 50 || reduceMotion {
                    run()
                } else {
                    NextUpChrome.perform(NextUpChrome.settle, reduceMotion: reduceMotion, run)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: editing) { _, isEditing in
            if isEditing {
                DispatchQueue.main.async { editFocused = true }
            } else {
                store.setTyping("edit-\(item.id)", active: false)
                store.setFieldOwnsUndo("edit-\(item.id)", active: false)
            }
        }
        .onChange(of: store.renameRequest) { _, id in
            guard id == item.id else { return }
            beginEditing()
            store.consumeRenameRequest()
        }
        .onDisappear {
            store.setTyping("edit-\(item.id)", active: false)
            store.setFieldOwnsUndo("edit-\(item.id)", active: false)
        }
        .onChange(of: item.status) { old, new in
            guard hasChildren, old != .done, new == .done else { return }
            parentCheckScale = reduceMotion ? 1 : NextUpChrome.parentCheckStart
            guard !reduceMotion else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(NextUpChrome.parentCheckDelay * 1_000_000_000))
                withAnimation(NextUpChrome.press) { parentCheckScale = 1 }
            }
        }
    }

    @ViewBuilder
    private var titleControl: some View {
        let label = HStack(spacing: 12) {
            if editing {
                TextField(Copy.text(.title, store.language), text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($editFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand { editing = false }
                    .onChange(of: editFocused) { _, focused in
                        store.setTyping("edit-\(item.id)", active: focused)
                        store.setFieldOwnsUndo("edit-\(item.id)", active: focused && editTitle != item.title)
                    }
                    .onChange(of: editTitle) { _, value in
                        store.setFieldOwnsUndo("edit-\(item.id)", active: editFocused && value != item.title)
                    }
            } else {
                Text(NextUpChrome.plainTitle(item.title))
                    .font(.system(size: NextUpChrome.taskSize, weight: hasChildren && item.status != .done ? .semibold : .regular))
                    .foregroundStyle(item.status == .done ? .secondary : .primary)
                    .strikethrough(item.status == .done, color: .secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 12)
            if item.status != .done, let text = trailing {
                Text(text)
                    .font(.system(size: NextUpChrome.dateSize).monospacedDigit())
                    .foregroundStyle(isOverdue ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 12)
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

    private var statusSymbol: some View {
        let symbol = Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(item.status == .done ? Color.secondary : Color.primary)
            .frame(width: 28, height: 28)
        return Group {
            if reduceMotion {
                symbol
            } else {
                symbol.contentTransition(.symbolEffect(.replace))
            }
        }
    }

    private var trailing: String? {
        let auxiliary = TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, now: Date(), calendar: .current, language: store.language)
        return auxiliary.text
    }

    private var isOverdue: Bool {
        TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, now: Date(), calendar: .current, language: store.language).emphasis == .overdue
    }

    private var hasChildren: Bool {
        store.document.items.contains { $0.parentID == item.id }
    }

    private func toggle() {
        store.setStatus(id: item.id, status: item.status == .done ? .todo : .done)
    }

    private var deletionIDs: Set<UUID> {
        store.selection.contains(item.id) && store.selection.count > 1 ? store.selection : [item.id]
    }

    private var deleteLabel: String {
        let count = deletionIDs.count
        return count > 1 ? Copy.undoDelete(count, store.language) : Copy.text(.delete, store.language)
    }

    private func beginEditing() {
        editTitle = item.title
        editing = true
    }

    private func commitEdit() {
        if store.rename(id: item.id, title: editTitle) {
            store.performWithoutUndo { editing = false }
        }
    }

    private func selectionPlate(color: Color, active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .padding(4)
            .scaleEffect(reduceMotion || active ? 1 : 0.98)
            .opacity(active ? 1 : 0)
            .animation(plateAnimation(active: active), value: active)
            .allowsHitTesting(false)
    }

    private func plateAnimation(active: Bool) -> Animation? {
        if reduceMotion { return nil }
        return active ? NextUpChrome.press : .easeOut(duration: 0.14)
    }

    private var pointer: some Gesture {
        DragGesture(minimumDistance: NextUpChrome.dragThreshold, coordinateSpace: .global)
            .onChanged { value in
                suppressTap = true
                onDrag(value.translation.height)
            }
            .onEnded { _ in
                onDragEnd()
                DispatchQueue.main.async { suppressTap = false }
            }
    }
}

private struct NextUpCircleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? NextUpChrome.pressScale : 1)
            .animation(NextUpChrome.resolved(NextUpChrome.press, reduceMotion: reduceMotion), value: configuration.isPressed)
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

struct NextUpAluminumFill: View {
    var window: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let surface = NextUpChrome.surface(window: window, dark: colorScheme == .dark)
        ZStack {
            LinearGradient(
                colors: [
                    Color(stop: surface.top),
                    Color(stop: surface.middle),
                    Color(stop: surface.bottom)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.white.opacity(surface.highlightOpacity), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: NextUpChrome.highlightHeight)
                Spacer(minLength: 0)
            }
        }
    }
}

private extension Color {
    init(stop: NextUpChrome.Stop) {
        self.init(red: stop.red, green: stop.green, blue: stop.blue)
    }
}

private struct KeyWindowProbe: NSViewRepresentable {
    var onChange: (NSWindow?, Bool) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: NSView {
        var onChange: ((NSWindow?, Bool) -> Void)?

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard window != nil else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(report), name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(report), name: NSWindow.didResignKeyNotification, object: nil)
            report()
        }

        @objc private func report() {
            onChange?(window, window?.isKeyWindow ?? false)
        }
    }
}
