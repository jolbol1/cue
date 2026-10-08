import Foundation

public enum FileSortOrder: String, Codable, CaseIterable {
    case nameAscending, nameDescending, modifiedNewest, modifiedOldest, createdNewest, createdOldest

    public var title: String {
        switch self {
        case .nameAscending: return "Name: A–Z"
        case .nameDescending: return "Name: Z–A"
        case .modifiedNewest: return "Modified: newest first"
        case .modifiedOldest: return "Modified: oldest first"
        case .createdNewest: return "Created: newest first"
        case .createdOldest: return "Created: oldest first"
        }
    }
}

public struct ScriptFileDates: Equatable {
    public let modified: Date?
    public let created: Date?
    public init(modified: Date? = nil, created: Date? = nil) { self.modified = modified; self.created = created }
}

public struct ScriptTreeNode: Identifiable, Equatable {
    public let path: String
    public let name: String
    public let children: [ScriptTreeNode]?
    public let dates: ScriptFileDates
    public var id: String { path }
    public var isFolder: Bool { children != nil }

    public init(path: String, name: String, children: [ScriptTreeNode]?, dates: ScriptFileDates = .init()) {
        self.path = path; self.name = name; self.children = children; self.dates = dates
    }

    public static func build(paths: [String], dates: [String: ScriptFileDates] = [:]) -> [ScriptTreeNode] {
        let root = Branch()
        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            var branch = root
            for name in components.dropLast() {
                if branch.folders[name] == nil { branch.folders[name] = Branch() }
                branch = branch.folders[name]!
            }
            branch.files.insert(components.last!)
        }
        return root.nodes(parent: "", dates: dates)
    }

    public static func filter(_ nodes: [ScriptTreeNode], query: String) -> [ScriptTreeNode] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nodes }
        return nodes.compactMap { node in
            if node.path.localizedCaseInsensitiveContains(query) { return node }
            guard let children = node.children else { return nil }
            let matches = filter(children, query: query)
            return matches.isEmpty ? nil : ScriptTreeNode(path: node.path, name: node.name, children: matches, dates: node.dates)
        }
    }

    public static func sorted(_ nodes: [ScriptTreeNode], by order: FileSortOrder) -> [ScriptTreeNode] {
        nodes.map { node in
            ScriptTreeNode(path: node.path, name: node.name,
                           children: node.children.map { sorted($0, by: order) }, dates: node.dates)
        }.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let names = a.name.localizedStandardCompare(b.name)
            if order == .nameAscending || order == .nameDescending {
                if names == .orderedSame { return a.path < b.path }
                return names == (order == .nameAscending ? .orderedAscending : .orderedDescending)
            }
            let creation = order == .createdNewest || order == .createdOldest
            let aDate = creation ? a.dates.created : a.dates.modified
            let bDate = creation ? b.dates.created : b.dates.modified
            switch (aDate, bDate) {
            case let (left?, right?) where left != right:
                return order == .createdNewest || order == .modifiedNewest ? left > right : left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return names == .orderedSame ? a.path < b.path : names == .orderedAscending
            }
        }
    }
}

private final class Branch {
    var folders: [String: Branch] = [:]
    var files = Set<String>()

    func nodes(parent: String, dates: [String: ScriptFileDates]) -> [ScriptTreeNode] {
        func path(_ name: String) -> String { parent.isEmpty ? name : parent + "/" + name }
        func ordered(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
        let directories = folders.keys.sorted(by: ordered).map { name in
            ScriptTreeNode(path: path(name), name: name, children: folders[name]!.nodes(parent: path(name), dates: dates), dates: dates[path(name)] ?? .init())
        }
        let documents = files.sorted(by: ordered).map { ScriptTreeNode(path: path($0), name: $0, children: nil, dates: dates[path($0)] ?? .init()) }
        return directories + documents
    }
}
