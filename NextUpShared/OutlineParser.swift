import Foundation

public struct OutlineEntry: Equatable, Sendable {
    public var title: String
    public var dueDate: String?
    public var assignee: String?
    public var children: [OutlineEntry]

    public init(title: String, dueDate: String? = nil, assignee: String? = nil, children: [OutlineEntry] = []) {
        self.title = title
        self.dueDate = dueDate
        self.assignee = assignee
        self.children = children
    }
}

public enum OutlineParser {
    public static func looksLikeOutline(_ raw: String) -> Bool {
        classifiedLines(raw).count >= 2
    }

    /// 超过这个条数先停住，等回车再写入。
    public static let pasteConfirmLimit = 20

    /// 会写成几条任务。嵌套行也各算一条。
    public static func entryCount(_ raw: String) -> Int {
        classifiedLines(raw).count
    }

    public static func parse(_ raw: String, now: Date, calendar: Calendar) -> [OutlineEntry] {
        let lines = classifiedLines(raw)
        guard !lines.isEmpty else { return [] }
        let year = calendar.component(.year, from: now)
        var roots: [Node] = []
        var stack: [Node] = []
        for line in lines {
            let decorated = decorate(line.body, year: year, calendar: calendar)
            let node = Node(level: line.level, title: decorated.title, dueDate: decorated.dueDate, assignee: decorated.assignee)
            while let last = stack.last, last.level >= line.level {
                stack.removeLast()
            }
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        }

        func entry(from node: Node) -> OutlineEntry {
            OutlineEntry(
                title: node.title,
                dueDate: node.dueDate,
                assignee: node.assignee,
                children: node.children.map(entry(from:))
            )
        }
        return roots.map(entry(from:))
    }

    private final class Node {
        let level: Int
        var title: String
        var dueDate: String?
        var assignee: String?
        var children: [Node] = []

        init(level: Int, title: String, dueDate: String?, assignee: String?) {
            self.level = level
            self.title = title
            self.dueDate = dueDate
            self.assignee = assignee
        }
    }

    private struct ClassifiedLine {
        var level: Int
        var body: String
    }

    private static func classifiedLines(_ raw: String) -> [ClassifiedLine] {
        raw.split(whereSeparator: \.isNewline).compactMap { fragment in
            let expanded = fragment.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = expanded.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let parsed = classify(trimmed) else { return nil }
            return parsed
        }
    }

    private static func classify(_ line: String) -> ClassifiedLine? {
        if let parts = capture(#"^(#{1,3})\s+(.+)$"#, line), parts.count == 3 {
            return ClassifiedLine(level: min(2, parts[1].count - 1), body: parts[2])
        }
        if let parts = capture(#"^([一二三四五六七八九十百零]+)[、.．]\s*(.+)$"#, line), parts.count == 3 {
            return ClassifiedLine(level: 0, body: parts[2])
        }
        if let parts = capture(#"^(\d+)[.、．]\s*(.+)$"#, line), parts.count == 3 {
            return ClassifiedLine(level: 1, body: parts[2])
        }
        if let parts = capture(#"^([A-Za-z])[.、．]\s*(.+)$"#, line), parts.count == 3 {
            return ClassifiedLine(level: 2, body: parts[2])
        }
        if let parts = capture(#"^[-*]\s+(.+)$"#, line), parts.count == 2 {
            return ClassifiedLine(level: 1, body: parts[1])
        }
        return nil
    }

    private static func decorate(_ body: String, year: Int, calendar: Calendar) -> (title: String, dueDate: String?, assignee: String?) {
        let title = body.trimmingCharacters(in: .whitespacesAndNewlines)
        var dueDate: String?
        if let parts = capture(#"[（(]\s*(\d{1,2})\s*[.．/]\s*(\d{1,2})"#, title), parts.count >= 3,
           let month = Int(parts[1]), let day = Int(parts[2]) {
            dueDate = DueDate.canonical(String(format: "%04d-%02d-%02d", year, month, day), calendar: calendar)
        }
        var assignee: String?
        if let parts = capture(#"@([A-Za-z][A-Za-z0-9_.-]*)"#, title), parts.count == 2 {
            assignee = parts[1]
        }
        return (title, dueDate, assignee)
    }

    private static func capture(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        if pattern.hasPrefix("^"), match.range.location != 0 { return nil }
        var parts: [String] = []
        for index in 0..<match.numberOfRanges {
            guard let slice = Range(match.range(at: index), in: text) else { return nil }
            parts.append(String(text[slice]))
        }
        return parts
    }
}
