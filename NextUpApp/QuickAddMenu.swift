import AppKit
import NextUpShared
import SwiftUI

struct QuickAddMenu: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.openWindow) private var openWindow
    @State private var title = ""
    @State private var failure: StoreError?
    @State private var pendingCount: Int?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: add) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(Copy.text(.add, store.language))
                    TextField(Copy.text(.menuPlaceholder, store.language), text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: NextUpChrome.taskSize))
                        .onSubmit(add)
                        .onExitCommand {
                            title = ""
                            failure = nil
                            pendingCount = nil
                            store.setFieldOwnsUndo("quick-add", active: false)
                        }
                        .onChange(of: title) { _, newValue in
                            let count = OutlineParser.entryCount(newValue)
                            pendingCount = count > OutlineParser.pasteConfirmLimit ? count : nil
                            store.setFieldOwnsUndo("quick-add", active: !newValue.isEmpty)
                        }
                }
                if let pendingCount {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.pendingPaste(pendingCount, store.language))
                            .font(.subheadline.weight(.medium))
                        Text(Copy.text(.pasteHint, store.language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(upcoming) { item in
                        Button {
                            openTask(item.id)
                        } label: {
                            upcomingRow(item)
                                .padding(.vertical, 6)
                                .nextUpClickable(cornerRadius: 8, horizontalPadding: 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let failure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Rectangle()
                    .fill(Color.primary.opacity(NextUpChrome.hairlineOpacity))
                    .frame(height: NextUpChrome.hairline)
                HStack(spacing: 14) {
                    Button(Copy.text(.openApp, store.language), action: openApp)
                        .buttonStyle(.plain)
                        .nextUpClickable(cornerRadius: 8, horizontalPadding: 6)
                    Button(Copy.text(.quitApp, store.language)) { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .nextUpClickable(cornerRadius: 8, horizontalPadding: 6)
                }
                .font(.system(size: NextUpChrome.dateSize))
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background {
            NextUpAluminumFill(window: true)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(NextUpChrome.hairlineOpacity), lineWidth: NextUpChrome.hairline)
        }
        .onAppear { store.reload() }
        .onDisappear { store.setFieldOwnsUndo("quick-add", active: false) }
    }

    private var upcoming: [TodoItem] {
        TodoSorting.widgetItems(store.document.items, limit: 3, now: Date(), calendar: .current)
    }

    private func upcomingRow(_ item: TodoItem) -> some View {
        let auxiliary = TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, now: Date(), calendar: .current, language: store.language)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(NextUpChrome.plainTitle(item.title))
                .font(.system(size: NextUpChrome.taskSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let text = auxiliary.text {
                Text(text)
                    .font(.system(size: NextUpChrome.dateSize).monospacedDigit())
                    .foregroundStyle(auxiliary.emphasis == .overdue ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .contentShape(Rectangle())
    }

    private func add() {
        guard !adding else { return }
        let submitted = title
        guard !submitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        adding = true
        defer { adding = false }
        do {
            if OutlineParser.looksLikeOutline(submitted) {
                try store.addOutline(submitted)
            } else {
                try store.add(title: submitted)
            }
            title = ""
            pendingCount = nil
            failure = nil
            store.setFieldOwnsUndo("quick-add", active: false)
        } catch let error as StoreError {
            failure = error
        } catch {
            failure = .writeFailed
        }
    }

    private func openTask(_ id: UUID) {
        store.highlightedID = id
        openWindow(id: "main")
        NSApp.activate()
    }

    private func openApp() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
