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

    init(item: TodoItem, now: Date, calendar: Calendar, depth: Int, canComplete: Bool, language: AppLanguage = .resolved) {
        let auxiliary = TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, now: now, calendar: calendar, language: language)
        self.id = item.id.uuidString
        self.title = WidgetRow.singleLine(item.title)
        self.trailing = auxiliary.text ?? ""
        self.isOverdue = auxiliary.emphasis == .overdue
        self.depth = depth
        self.canComplete = canComplete
    }

    static func singleLine(_ title: String) -> String {
        NextUpChrome.plainTitle(title)
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

    static var preview: WidgetEntry {
        let waiting = Copy.text(.waiting, AppLanguage.resolved)
        return WidgetEntry(
            date: .now,
            unfinishedCount: 5,
            rows: [
                WidgetRow(id: "preview-1", title: "与 Allen 对齐 BD 排期", trailing: "10/14", isOverdue: false),
                WidgetRow(id: "preview-2", title: "确认 CashBack 发版事项", trailing: "10/15", isOverdue: false),
                WidgetRow(id: "preview-3", title: "更新 i18n 方案", trailing: waiting, isOverdue: false)
            ],
            largeRows: [
                WidgetRow(id: "preview-1", title: "与 Allen 对齐 BD 排期", trailing: "10/14", isOverdue: false, canComplete: false),
                WidgetRow(id: "preview-1a", title: "确认接口字段", trailing: "", isOverdue: false, depth: 1),
                WidgetRow(id: "preview-1b", title: "约下次评审", trailing: "", isOverdue: false, depth: 1),
                WidgetRow(id: "preview-2", title: "确认 CashBack 发版事项", trailing: "10/15", isOverdue: false),
                WidgetRow(id: "preview-3", title: "更新 i18n 方案", trailing: waiting, isOverdue: false)
            ],
            isReadFailure: false
        )
    }

    static var longTitle: WidgetEntry {
        let overdue = Copy.text(.overdue, AppLanguage.resolved)
        return WidgetEntry(
            date: .now,
            unfinishedCount: 1,
            rows: [
                WidgetRow(
                    id: "preview-long",
                    title: "这是一条非常长的任务标题，用来确认右侧日期不会被挤出卡片",
                    trailing: overdue,
                    isOverdue: true
                )
            ],
            largeRows: [
                WidgetRow(
                    id: "preview-long",
                    title: "这是一条非常长的任务标题，用来确认右侧日期不会被挤出卡片",
                    trailing: overdue,
                    isOverdue: true
                )
            ],
            isReadFailure: false
        )
    }
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

    private var language: AppLanguage { AppLanguage.resolved }

    private var visibleRows: [WidgetRow] {
        family == .systemLarge ? entry.largeRows : entry.rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, NextUpChrome.widgetHeaderGap)
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
            Text(Copy.text(.windowTitle, language))
                .font(.system(size: NextUpChrome.taskSize, weight: .semibold))
                .foregroundStyle(.primary)
                .widgetAccentable()
            Spacer(minLength: 12)
            if !entry.isReadFailure {
                Text(Copy.openCount(entry.unfinishedCount, language))
                    .font(.system(size: NextUpChrome.dateSize).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.isReadFailure ? Copy.text(.windowTitle, language) : Copy.unfinishedLabel(entry.unfinishedCount, language))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text(Copy.text(.allDone, language))
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
            Text(Copy.text(.tapToOpen, language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(openURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.text(.allDoneHint, language))
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text(Copy.text(.readFailed, language))
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
            Text(Copy.text(.tapToOpen, language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(openURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.text(.readFailedHint, language))
    }

    private func taskRow(_ row: WidgetRow, isNewGroup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isNewGroup {
                Rectangle()
                    .fill(Color.primary.opacity(NextUpChrome.hairlineOpacity))
                    .frame(height: NextUpChrome.hairline)
                    .padding(.top, NextUpChrome.widgetDividerTop)
                    .padding(.bottom, NextUpChrome.widgetDividerBottom)
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
                    .accessibilityLabel(Copy.complete(row.title, language))
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
            .padding(.top, isNewGroup ? NextUpChrome.widgetGroupRowGap : NextUpChrome.widgetRowGap)
            .padding(.leading, CGFloat(row.depth) * NextUpChrome.widgetIndent)
        }
    }

    private func rowLabel(_ row: WidgetRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(WidgetRow.singleLine(row.title))
                .font(.system(size: NextUpChrome.taskSize, weight: row.canComplete ? .regular : .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !row.trailing.isEmpty {
                Text(row.trailing)
                    .font(.system(size: NextUpChrome.dateSize).monospacedDigit())
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
        let surface = NextUpChrome.surface(window: false, dark: colorScheme == .dark)
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
                    colors: [Color.white.opacity(surface.highlightOpacity), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: NextUpChrome.highlightHeight)
                Spacer(minLength: 0)
            }
            ContainerRelativeShape()
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.20 : 0.50),
                    lineWidth: NextUpChrome.hairline
                )
        }
    }
}

private extension Color {
    init(stop: NextUpChrome.Stop) {
        self.init(red: stop.red, green: stop.green, blue: stop.blue)
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
        .configurationDisplayName(Copy.text(.windowTitle, AppLanguage.resolved))
        .description(Copy.text(.widgetDescription, AppLanguage.resolved))
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
