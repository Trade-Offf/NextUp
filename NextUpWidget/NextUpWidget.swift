import WidgetKit
import SwiftUI
import NextUpShared

struct WidgetRow: Identifiable {
    let id: String
    let title: String
    let trailing: String
    let isOverdue: Bool
    let depth: Int
    let canComplete: Bool

    init(id: String, title: String, trailing: String, isOverdue: Bool, depth: Int = 0, canComplete: Bool = true) {
        self.id = id
        self.title = title
        self.trailing = trailing
        self.isOverdue = isOverdue
        self.depth = depth
        self.canComplete = canComplete
    }

    init(item: TodoItem, now: Date, calendar: Calendar, depth: Int, canComplete: Bool) {
        let auxiliary = TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, now: now, calendar: calendar)
        self.id = item.id.uuidString
        self.title = WidgetRow.singleLine(item.title)
        self.trailing = auxiliary.text ?? ""
        self.isOverdue = auxiliary.emphasis == .overdue
        self.depth = depth
        self.canComplete = canComplete
    }

    static func singleLine(_ title: String) -> String {
        title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\u{2028}", with: " ")
            .replacingOccurrences(of: "\u{2029}", with: " ")
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let unfinishedCount: Int
    let rows: [WidgetRow]
    let largeRows: [WidgetRow]
    let isReadFailure: Bool

    static func empty(date: Date) -> WidgetEntry {
        WidgetEntry(date: date, unfinishedCount: 0, rows: [], largeRows: [], isReadFailure: false)
    }

    static func readFailure(date: Date) -> WidgetEntry {
        WidgetEntry(date: date, unfinishedCount: 0, rows: [], largeRows: [], isReadFailure: true)
    }

    static let preview = WidgetEntry(
        date: .now,
        unfinishedCount: 5,
        rows: [
            WidgetRow(id: "preview-1", title: "与 Allen 对齐 BD 排期", trailing: "10/14", isOverdue: false),
            WidgetRow(id: "preview-2", title: "确认 CashBack 发版事项", trailing: "10/15", isOverdue: false),
            WidgetRow(id: "preview-3", title: "更新 i18n 方案", trailing: "等待反馈", isOverdue: false)
        ],
        largeRows: [
            WidgetRow(id: "preview-1", title: "与 Allen 对齐 BD 排期", trailing: "10/14", isOverdue: false, canComplete: false),
            WidgetRow(id: "preview-1a", title: "确认接口字段", trailing: "", isOverdue: false, depth: 1),
            WidgetRow(id: "preview-1b", title: "约下次评审", trailing: "", isOverdue: false, depth: 1),
            WidgetRow(id: "preview-2", title: "确认 CashBack 发版事项", trailing: "10/15", isOverdue: false),
            WidgetRow(id: "preview-3", title: "更新 i18n 方案", trailing: "等待反馈", isOverdue: false)
        ],
        isReadFailure: false
    )

    static let longTitle = WidgetEntry(
        date: .now,
        unfinishedCount: 1,
        rows: [
            WidgetRow(
                id: "preview-long",
                title: "这是一条非常长的任务标题，用来确认右侧日期不会被挤出卡片",
                trailing: "已逾期",
                isOverdue: true
            )
        ],
        largeRows: [
            WidgetRow(
                id: "preview-long",
                title: "这是一条非常长的任务标题，用来确认右侧日期不会被挤出卡片",
                trailing: "已逾期",
                isOverdue: true
            )
        ],
        isReadFailure: false
    )
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        loadEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date()
        let entry = loadEntry(now: now)
        let nextMidnight = DueDate.nextLocalMidnight(after: now, calendar: .current)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func loadEntry(now: Date = Date()) -> WidgetEntry {
        do {
            // let repository = try TodoRepository.inAppGroup()
            let repository = try TodoRepository.localStore()
            let items = try repository.load().items
            let calendar = Calendar.current
            let rows = widgetRows(items, limit: 3, now: now, calendar: calendar)
            return WidgetEntry(
                date: now,
                unfinishedCount: TodoSorting.incompleteCount(items),
                rows: rows,
                largeRows: largeWidgetRows(items, now: now, calendar: calendar),
                isReadFailure: false
            )
        } catch {
            return .readFailure(date: now)
        }
    }

    private func widgetRows(_ items: [TodoItem], limit: Int, now: Date, calendar: Calendar) -> [WidgetRow] {
        TodoSorting.widgetItems(items, limit: limit, now: now, calendar: calendar).map { item in
            WidgetRow(
                item: item,
                now: now,
                calendar: calendar,
                depth: 0,
                canComplete: !items.contains { $0.parentID == item.id }
            )
        }
    }

    private func largeWidgetRows(_ items: [TodoItem], now: Date, calendar: Calendar) -> [WidgetRow] {
        let parents = TodoSorting.widgetItems(items, limit: 7, now: now, calendar: calendar)
        var rows: [WidgetRow] = []
        func visit(_ item: TodoItem, depth: Int) {
            guard rows.count < 16 else { return }
            let hasChildren = items.contains { $0.parentID == item.id }
            rows.append(
                WidgetRow(
                    item: item,
                    now: now,
                    calendar: calendar,
                    depth: depth,
                    canComplete: !hasChildren
                )
            )
            let children = items
                .filter { $0.parentID == item.id && $0.status != .done }
                .sorted { TodoSorting.isOrderedBefore($0, $1, now: now, calendar: calendar) }
            for child in children {
                visit(child, depth: depth + 1)
            }
        }
        for parent in parents {
            guard rows.count < 16 else { break }
            visit(parent, depth: 0)
        }
        return rows
    }
}

struct NextUpWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    private var visibleRows: [WidgetRow] {
        family == .systemLarge ? entry.largeRows : entry.rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)
            if entry.isReadFailure {
                failure
            } else if visibleRows.isEmpty {
                empty
            } else {
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                    taskRow(row, isNewGroup: index > 0 && row.depth == 0)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("接下来")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .widgetAccentable()
            Spacer(minLength: 12)
            if !entry.isReadFailure {
                Text("\(entry.unfinishedCount) 项")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.isReadFailure ? "接下来" : "接下来，\(entry.unfinishedCount) 项未完成")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text("都处理好了")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
            Text("点击打开 Next Up")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(openURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("都处理好了。点击打开 Next Up")
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text("暂时无法读取任务")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
            Text("点击打开 Next Up")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(openURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("暂时无法读取任务。点击打开 Next Up")
    }

    private func taskRow(_ row: WidgetRow, isNewGroup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isNewGroup {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 0.5)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .center, spacing: 6) {
                if row.canComplete {
                    Button(intent: CompleteTodoIntent(itemID: row.id)) {
                        Image(systemName: "circle")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("完成：\(row.title)")
                } else {
                    Color.clear
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }

                if let destination = taskURL(for: row.id) {
                    Link(destination: destination) {
                        rowLabel(row)
                    }
                    .buttonStyle(.plain)
                } else {
                    rowLabel(row)
                }
            }
            .padding(.top, isNewGroup ? 2 : 6)
            .padding(.leading, CGFloat(row.depth) * 16)
        }
    }

    private func rowLabel(_ row: WidgetRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(WidgetRow.singleLine(row.title))
                .font(.system(size: 13, weight: row.canComplete ? .regular : .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !row.trailing.isEmpty {
                Text(row.trailing)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(row.isOverdue ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.trailing.isEmpty ? row.title : "\(row.title)，\(row.trailing)")
    }

    private var openURL: URL? {
        URL(string: "\(AppIdentity.urlScheme())://open")
    }

    private func taskURL(for id: String) -> URL? {
        URL(string: "\(AppIdentity.urlScheme())://task/\(id)")
    }
}

private struct MetalCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let graphite = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: graphite
                    ? [
                        Color(red: 0.24, green: 0.25, blue: 0.27),
                        Color(red: 0.14, green: 0.15, blue: 0.16),
                        Color(red: 0.18, green: 0.19, blue: 0.20)
                    ]
                    : [
                        Color(red: 0.94, green: 0.95, blue: 0.96),
                        Color(red: 0.78, green: 0.80, blue: 0.83),
                        Color(red: 0.86, green: 0.88, blue: 0.90)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.white.opacity(graphite ? 0.16 : 0.55), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 22)
                Spacer(minLength: 0)
            }
            ContainerRelativeShape()
                .strokeBorder(Color.white.opacity(graphite ? 0.20 : 0.50), lineWidth: 0.5)
        }
    }
}

struct NextUpWidget: Widget {
    let kind: String = AppIdentity.widgetKind()

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextUpProvider()) { entry in
            NextUpWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    MetalCardBackground()
                }
        }
        .configurationDisplayName("Next Up")
        .description("打开通知中心，看接下来最值得关注的几件事。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    NextUpWidget()
} timeline: {
    WidgetEntry.preview
    WidgetEntry.longTitle
    WidgetEntry.empty(date: .now)
    WidgetEntry.readFailure(date: .now)
}

#Preview(as: .systemLarge) {
    NextUpWidget()
} timeline: {
    WidgetEntry.preview
    WidgetEntry.longTitle
    WidgetEntry.empty(date: .now)
    WidgetEntry.readFailure(date: .now)
}
