import AppKit
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
        let auxiliary = TaskAuxiliaryText.make(status: item.status, dueDate: item.dueDate, dueTime: item.dueTime, now: now, calendar: calendar, language: language)
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
    let stats: WidgetStats
    let largeRows: [WidgetRow]
    let isReadFailure: Bool
    let celebrates: Bool
    let showsBadge: Bool

    static let celebrationDuration: TimeInterval = 4

    static func empty(date: Date) -> WidgetEntry {
        WidgetEntry(date: date, unfinishedCount: 0, stats: .zero, largeRows: [], isReadFailure: false, celebrates: false, showsBadge: false)
    }

    static func readFailure(date: Date) -> WidgetEntry {
        WidgetEntry(date: date, unfinishedCount: 0, stats: .zero, largeRows: [], isReadFailure: true, celebrates: false, showsBadge: false)
    }

    static var preview: WidgetEntry {
        let waiting = Copy.text(.waiting, AppLanguage.resolved)
        return WidgetEntry(
            date: .now,
            unfinishedCount: 5,
            stats: WidgetStats(unfinished: 5, overdue: 1, today: 2, upcoming: 1, undated: 1),
            largeRows: [
                WidgetRow(id: "preview-1", title: "与 Allen 对齐 BD 排期", trailing: "10/14", isOverdue: false, canComplete: false),
                WidgetRow(id: "preview-1a", title: "确认接口字段", trailing: "", isOverdue: false, depth: 1),
                WidgetRow(id: "preview-1b", title: "约下次评审", trailing: "", isOverdue: false, depth: 1),
                WidgetRow(id: "preview-2", title: "确认 CashBack 发版事项", trailing: "10/15", isOverdue: false),
                WidgetRow(id: "preview-3", title: "更新 i18n 方案", trailing: waiting, isOverdue: false)
            ],
            isReadFailure: false,
            celebrates: false,
            showsBadge: false
        )
    }

    static var longTitle: WidgetEntry {
        let overdue = Copy.text(.overdue, AppLanguage.resolved)
        return WidgetEntry(
            date: .now,
            unfinishedCount: 1,
            stats: WidgetStats(unfinished: 1, overdue: 1, today: 0, upcoming: 0, undated: 0),
            largeRows: [
                WidgetRow(
                    id: "preview-long",
                    title: "这是一条非常长的任务标题，用来确认右侧日期不会被挤出卡片",
                    trailing: overdue,
                    isOverdue: true
                )
            ],
            isReadFailure: false,
            celebrates: false,
            showsBadge: false
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
        let nextMidnight = DueDate.nextLocalMidnight(after: now, calendar: .current)
        guard let items = try? TodoRepository.localStore().load().items else {
            completion(Timeline(entries: [.readFailure(date: now)], policy: .after(nextMidnight)))
            return
        }
        var moments: [Date] = []
        if AppPreferences.showsWidgetBadge(), let latest = items.compactMap(\.completedAt).max() {
            let until = latest.addingTimeInterval(WidgetEntry.celebrationDuration)
            if until > now {
                moments.append(until)
            }
        }
        moments.append(contentsOf: TodoSorting.clockDeadlines(items, after: now, before: nextMidnight, calendar: .current))
        var entries = [loadEntry(now: now, items: items)]
        for moment in moments.sorted() where moment > (entries.last?.date ?? now) {
            entries.append(loadEntry(now: moment, items: items))
        }
        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
    }

    private func loadEntry(now: Date = Date(), items: [TodoItem]? = nil) -> WidgetEntry {
        do {
            let resolved = try items ?? TodoRepository.localStore().load().items
            let calendar = Calendar.current
            let stats = TodoSorting.widgetStats(resolved, now: now, calendar: calendar)
            let showsBadge = AppPreferences.showsWidgetBadge()
            let latest = resolved.compactMap(\.completedAt).max()
            let celebrates = showsBadge && (latest.map { now.timeIntervalSince($0) < WidgetEntry.celebrationDuration && now.timeIntervalSince($0) > -1 } ?? false)
            return WidgetEntry(
                date: now,
                unfinishedCount: stats.unfinished,
                stats: stats,
                largeRows: largeWidgetRows(resolved, now: now, calendar: calendar),
                isReadFailure: false,
                celebrates: celebrates,
                showsBadge: showsBadge
            )
        } catch {
            return .readFailure(date: now)
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
        entry.largeRows
    }

    var body: some View {
        Group {
            if family == .systemLarge {
                largeBody
            } else {
                mediumBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(showsCount: false)
            Group {
                if entry.isReadFailure {
                    failure
                } else if entry.stats.unfinished == 0 {
                    empty
                } else {
                    statistics
                }
            }
            .overlay(alignment: .topTrailing) {
                if entry.showsBadge && (entry.isReadFailure || entry.stats.unfinished == 0) {
                    brandBadge
                }
            }
        }
    }

    private var largeBody: some View {
        Group {
            if entry.isReadFailure {
                VStack(alignment: .leading, spacing: 0) {
                    header(showsCount: false)
                    failure
                }
            } else if visibleRows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    header(showsCount: true)
                    empty
                }
            } else {
                GeometryReader { proxy in
                    let shown = rowsThatFit(in: proxy.size.height)
                    VStack(alignment: .leading, spacing: 0) {
                        header(showsCount: true)
                        ForEach(Array(shown.rows.enumerated()), id: \.element.id) { index, row in
                            taskRow(row, isNewGroup: index > 0 && row.depth == 0)
                        }
                        if shown.more > 0 {
                            moreLink(shown.more)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
        }
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(entry.stats.unfinished)")
                        .font(.system(size: 36, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .widgetAccentable()
                    Text(Copy.text(.widgetOpenItems, language))
                        .font(.system(size: NextUpChrome.dateSize))
                        .foregroundStyle(.secondary)
                }
                if entry.showsBadge {
                    Spacer(minLength: 8)
                    brandBadge
                }
            }
            HStack(alignment: .top, spacing: 0) {
                statCell(Copy.text(.overdue, language), entry.stats.overdue, emphasized: entry.stats.overdue > 0)
                statCell(Copy.text(.today, language), entry.stats.today, emphasized: false)
                statCell(Copy.text(.widgetUpcoming, language), entry.stats.upcoming, emphasized: false)
                statCell(Copy.text(.widgetUndated, language), entry.stats.undated, emphasized: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(openURL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statisticsLabel)
    }

    private func statCell(_ title: String, _ value: Int, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(value)")
                .font(.system(size: NextUpChrome.taskSize, weight: .medium).monospacedDigit())
                .foregroundStyle(emphasized ? Color.orange : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statisticsLabel: String {
        let stats = entry.stats
        let parts = [
            Copy.unfinishedLabel(stats.unfinished, language),
            "\(Copy.text(.overdue, language)) \(stats.overdue)",
            "\(Copy.text(.today, language)) \(stats.today)",
            "\(Copy.text(.widgetUpcoming, language)) \(stats.upcoming)",
            "\(Copy.text(.widgetUndated, language)) \(stats.undated)"
        ]
        return parts.joined(separator: "，")
    }

    private func rowsThatFit(in height: CGFloat) -> (rows: [WidgetRow], more: Int) {
        let starts = visibleRows.enumerated().map { index, row in index > 0 && row.depth == 0 }
        let choice = WidgetFit.choose(
            rowCount: visibleRows.count,
            total: entry.unfinishedCount,
            groupStarts: starts,
            height: max(0, height - 4),
            metrics: Self.rowMetrics,
            countsTowardTotal: visibleRows.map(\.canComplete)
        )
        return (Array(visibleRows.prefix(choice.shown)), choice.more)
    }

    private static var rowMetrics: WidgetFit.Metrics {
        let task = lineHeight(NextUpChrome.taskSize)
        let date = lineHeight(NextUpChrome.dateSize)
        let body = max(16, task)
        return WidgetFit.Metrics(
            header: task + NextUpChrome.widgetHeaderGap,
            row: NextUpChrome.widgetRowGap + body + 2,
            groupExtra: NextUpChrome.widgetDividerTop
                + NextUpChrome.hairline
                + NextUpChrome.widgetDividerBottom
                + NextUpChrome.widgetGroupRowGap
                - NextUpChrome.widgetRowGap,
            footer: NextUpChrome.widgetHeaderGap + date + 2
        )
    }

    private static func lineHeight(_ size: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size)
        return ceil(font.ascender - font.descender + font.leading)
    }

    private func moreLink(_ count: Int) -> some View {
        Group {
            if let openURL {
                Link(destination: openURL) {
                    moreLabel(count)
                }
                .buttonStyle(.plain)
            } else {
                moreLabel(count)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.widgetMore(count, language))
        .accessibilityAddTraits(.isLink)
    }

    private func moreLabel(_ count: Int) -> some View {
        Text(Copy.widgetMore(count, language))
            .font(.system(size: NextUpChrome.dateSize))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, NextUpChrome.widgetHeaderGap)
    }

    private var brandBadge: some View {
        Image(entry.celebrates ? "WidgetBadgeDone" : "WidgetBadge")
            .resizable()
            .scaledToFit()
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }

    private func header(showsCount: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Copy.text(.windowTitle, language))
                .font(.system(size: NextUpChrome.taskSize, weight: .semibold))
                .foregroundStyle(.primary)
                .widgetAccentable()
            Spacer(minLength: 12)
            if showsCount, !entry.isReadFailure {
                Text(Copy.openCount(entry.unfinishedCount, language))
                    .font(.system(size: NextUpChrome.dateSize).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .padding(.bottom, NextUpChrome.widgetHeaderGap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.isReadFailure || !showsCount ? Copy.text(.windowTitle, language) : Copy.unfinishedLabel(entry.unfinishedCount, language))
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

private struct WidgetChrome: View {
    let entry: WidgetEntry

    var body: some View {
        NextUpWidgetView(entry: entry)
            .containerBackground(for: .widget) {
                MetalCardBackground()
            }
    }
}

struct NextUpCountWidget: Widget {
    let kind: String = AppIdentity.countWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextUpProvider()) { entry in
            WidgetChrome(entry: entry)
        }
        .configurationDisplayName(Copy.text(.widgetCountName, AppLanguage.resolved))
        .description(Copy.text(.widgetCountDescription, AppLanguage.resolved))
        .supportedFamilies([.systemMedium])
    }
}

struct NextUpListWidget: Widget {
    let kind: String = AppIdentity.listWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextUpProvider()) { entry in
            WidgetChrome(entry: entry)
        }
        .configurationDisplayName(Copy.text(.widgetListName, AppLanguage.resolved))
        .description(Copy.text(.widgetListDescription, AppLanguage.resolved))
        .supportedFamilies([.systemLarge])
    }
}

#Preview(as: .systemMedium) {
    NextUpCountWidget()
} timeline: {
    WidgetEntry.preview
    WidgetEntry.longTitle
    WidgetEntry.empty(date: .now)
    WidgetEntry.readFailure(date: .now)
}

#Preview(as: .systemLarge) {
    NextUpListWidget()
} timeline: {
    WidgetEntry.preview
    WidgetEntry.longTitle
    WidgetEntry.empty(date: .now)
    WidgetEntry.readFailure(date: .now)
}
