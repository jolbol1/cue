import AppKit
import SwiftUI
import PrompterCore

/// A native outline keeps folder disclosure, keyboard navigation and scrolling familiar.
struct ScriptBrowser: NSViewRepresentable {
    let nodes: [ScriptTreeNode]
    let folder: String
    let query: String
    let sortOrder: FileSortOrder
    let selectedURL: URL?
    let openFile: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("filename"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.headerView = nil; outline.style = .sourceList; outline.rowSizeStyle = .default
        outline.backgroundColor = .clear; outline.focusRingType = .none
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.dataSource = context.coordinator; outline.delegate = context.coordinator
        outline.target = context.coordinator; outline.doubleAction = #selector(Coordinator.openFolder)
        outline.setAccessibilityLabel("Markdown files and folders")
        let menu = NSMenu()
        for (title, action) in [("Open in Default App", #selector(Coordinator.openExternally)), ("Show in Finder", #selector(Coordinator.showInFinder))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = context.coordinator
        }
        outline.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = outline; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        context.coordinator.outline = outline
        // Start with the file list focused rather than the search field above it.
        DispatchQueue.main.async { [weak outline] in outline?.window?.makeFirstResponder(outline) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(self) }

    final class Item: NSObject {
        let node: ScriptTreeNode
        let children: [Item]
        init(_ node: ScriptTreeNode) { self.node = node; children = (node.children ?? []).map(Item.init) }
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuItemValidation {
        weak var outline: NSOutlineView?
        var items: [Item] = []
        var previousNodes: [ScriptTreeNode] = []
        var folder = ""
        var query = ""
        var sortOrder = FileSortOrder.nameAscending
        var selectedURL: URL?
        var expanded = Set<String>()
        var updating = false
        var openFile: ((URL) -> Void)?

        func update(_ browser: ScriptBrowser) {
            guard let outline else { return }
            openFile = browser.openFile
            let query = browser.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let rootChanged = folder != browser.folder
            let treeChanged = rootChanged || previousNodes != browser.nodes || self.query != query || sortOrder != browser.sortOrder
            let selectionChanged = selectedURL != browser.selectedURL
            updating = true
            defer { updating = false }
            if rootChanged { expanded.removeAll() }
            folder = browser.folder; self.query = query; sortOrder = browser.sortOrder
            if treeChanged {
                previousNodes = browser.nodes
                items = ScriptTreeNode.sorted(ScriptTreeNode.filter(browser.nodes, query: query), by: sortOrder).map(Item.init)
                outline.reloadData()
                if query.isEmpty { restoreExpansion(items) }
                else { outline.expandItem(nil, expandChildren: true) }
            }
            if treeChanged || selectionChanged {
                selectedURL = browser.selectedURL
                if let url = selectedURL {
                    let prefix = URL(fileURLWithPath: folder).standardizedFileURL.path + "/"
                    let path = url.standardizedFileURL.path
                    if path.hasPrefix(prefix), let chain = find(String(path.dropFirst(prefix.count)), in: items) {
                        for ancestor in chain.dropLast() {
                            outline.expandItem(ancestor)
                            if query.isEmpty { expanded.insert(ancestor.node.path) }
                        }
                        let row = outline.row(forItem: chain.last!)
                        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); outline.scrollRowToVisible(row) }
                    }
                }
            }
        }

        func restoreExpansion(_ nodes: [Item]) {
            for item in nodes where item.node.isFolder {
                if expanded.contains(item.node.path) { outline?.expandItem(item); restoreExpansion(item.children) }
            }
        }
        func find(_ path: String, in items: [Item]) -> [Item]? {
            for item in items {
                if item.node.path == path { return [item] }
                if path.hasPrefix(item.node.path + "/"), let children = find(path, in: item.children) { return [item] + children }
            }
            return nil
        }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Item)?.children.count ?? items.count }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Item)?.children ?? items)[index] }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Item)?.node.isFolder ?? false }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("fileRow")
            let cell: NSTableCellView
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView { cell = reused }
            else {
                cell = NSTableCellView(); cell.identifier = identifier
                let image = NSImageView(); image.translatesAutoresizingMaskIntoConstraints = false
                let label = NSTextField(labelWithString: ""); label.translatesAutoresizingMaskIntoConstraints = false
                label.lineBreakMode = .byTruncatingMiddle
                cell.addSubview(image); cell.addSubview(label); cell.imageView = image; cell.textField = label
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16), image.heightAnchor.constraint(equalToConstant: 16),
                    label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 7),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            cell.textField?.stringValue = item.node.name
            cell.imageView?.image = NSImage(systemSymbolName: item.node.isFolder ? "folder" : "doc.text", accessibilityDescription: item.node.isFolder ? "Folder" : "Markdown file")
            cell.imageView?.contentTintColor = item.node.isFolder ? .controlAccentColor : .secondaryLabelColor
            cell.toolTip = url(for: item).path
            return cell
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let outline, let item = outline.item(atRow: outline.selectedRow) as? Item, !item.node.isFolder else { return }
            let fileURL = url(for: item)
            if fileURL != selectedURL { openFile?(fileURL) }
        }
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !updating, query.isEmpty, let item = notification.userInfo?["NSObject"] as? Item else { return }
            expanded.insert(item.node.path)
        }
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !updating, query.isEmpty, let item = notification.userInfo?["NSObject"] as? Item else { return }
            expanded.remove(item.node.path)
        }
        func url(for item: Item) -> URL { URL(fileURLWithPath: folder).appendingPathComponent(item.node.path) }
        var clickedItem: Item? { outline.flatMap { $0.item(atRow: $0.clickedRow) as? Item } }
        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { clickedItem != nil }
        @objc func openExternally() { if let item = clickedItem { NSWorkspace.shared.open(url(for: item)) } }
        @objc func showInFinder() { if let item = clickedItem { NSWorkspace.shared.activateFileViewerSelecting([url(for: item)]) } }
        @objc func openFolder() {
            guard let outline, let item = outline.item(atRow: outline.clickedRow) as? Item, item.node.isFolder else { return }
            if outline.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) }
        }
    }
}

/// A native search field for the sidebar; `.searchable` can't attach to an AppKit outline.
struct SidebarSearchField: NSViewRepresentable {
    static let focusRequest = Notification.Name("Cue.FocusSidebarSearch")
    @Binding var text: String
    let prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt; field.sendsSearchStringImmediately = true
        // The action also fires when the clear button empties the field, unlike text-change notifications.
        field.target = context.coordinator; field.action = #selector(Coordinator.searchChanged(_:))
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: Self.focusRequest, object: nil, queue: .main) { [weak field] _ in
            field?.window?.makeFirstResponder(field)
        }
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }
    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
    }

    final class Coordinator: NSObject {
        var text: Binding<String>
        var observer: NSObjectProtocol?
        init(text: Binding<String>) { self.text = text }
        @objc func searchChanged(_ field: NSSearchField) { text.wrappedValue = field.stringValue }
    }
}
