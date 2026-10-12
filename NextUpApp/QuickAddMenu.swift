import AppKit
import NextUpShared
import SwiftUI

struct QuickAddMenu: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.openWindow) private var openWindow
    @State private var title = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("接下来")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                TextField("记下下一件事…", text: $title)
                    .textFieldStyle(.plain)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .nextUpClickableCircle()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.defaultAction)
                .help("添加")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(upcoming) { item in
                        Button {
                            openTask(item.id)
                        } label: {
                            upcomingRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Button("打开 Next Up", action: openApp)
                    .buttonStyle(.plain)
                    .nextUpClickable(cornerRadius: 8, horizontalPadding: 6)
                Button("退出 Next Up") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .nextUpClickable(cornerRadius: 8, horizontalPadding: 6)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .onAppear { store.reload() }
    }

    private var upcoming: [TodoItem] {
        TodoSorting.widgetItems(store.document.items, limit: 3, now: Date(), calendar: .current)
    }

    private func upcomingRow(_ item: TodoItem) -> some View {
        let auxiliary = TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, now: Date(), calendar: .current)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.title.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let text = auxiliary.text {
                Text(text)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(auxiliary.emphasis == .overdue ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .contentShape(Rectangle())
    }

    private func add() {
        do {
            if OutlineParser.looksLikeOutline(title) {
                try store.addOutline(title)
            } else {
                try store.add(title: title)
            }
            title = ""
            errorMessage = nil
        } catch let error as StoreError {
            errorMessage = error.message
        } catch {
            errorMessage = StoreError.writeFailed.message
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
