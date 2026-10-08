import SwiftUI
import AppKit
import PrompterCore

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @AppStorage("Cue.ShowsInspector") private var showsInspector = true

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, search: $search)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 380)
        } detail: {
            // A zero minimum keeps the detail column's size constraints independent of its
            // content. Otherwise macOS 26+ can loop updating split view constraints and abort.
            StageView(model: model)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .inspector(isPresented: $showsInspector) {
                    InspectorView(model: model)
                        .inspectorColumnWidth(min: 300, ideal: 320, max: 420)
                }
                .toolbar { toolbar }
        }
        .navigationTitle(model.selectedURL?.deletingLastPathComponent().lastPathComponent ?? "Cue")
        .navigationSubtitle(model.selectedURL.map { "\($0.lastPathComponent) · \(model.fileStatus)" } ?? "")
        .frame(minWidth: 980, minHeight: 640)
        .onChange(of: model.settings.displayID) { model.updateCanvas(); if model.isProjecting { model.output.show() } }
        .onDisappear(perform: model.stopProjection)
        .alert("Cue", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(Array(model.headings.enumerated()), id: \.offset) { index, title in
                    Button(title) { model.jumpToHeading(index) }
                }
            } label: {
                Label("Sections", systemImage: "list.bullet.indent")
            }
            .accessibilityLabel("Sections")
            .disabled(model.headings.isEmpty)
            .help("Jump to a heading")

            Toggle(isOn: Binding(get: { model.blanked }, set: { _ in model.toggleBlackout() })) {
                Label("Blackout", systemImage: "eye.slash")
            }
            .disabled(!model.isProjecting)
            .help(model.blanked ? "Show the script on the output (⌃⌥⌘B)" : "Hide the script on the output (⌃⌥⌘B)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: model.toggleProjection) {
                Label(model.isProjecting ? "Stop" : "Project", systemImage: model.isProjecting ? "stop.fill" : "display")
                    .labelStyle(.titleAndIcon)
            }
            .prominentButtonStyle()
            .tint(model.isProjecting ? .red : .accentColor)
            .disabled(!model.isProjecting && (model.blocks.isEmpty || model.screens.isEmpty))
            .help(model.isProjecting ? "Stop projecting (⌃⌥⌘P, or Esc with the pointer on the output)" : "Show the script on \(model.selectedScreen?.localizedName ?? "the output display") (⌃⌥⌘P)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showsInspector.toggle() } label: {
                Label(showsInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .help(showsInspector ? "Hide inspector" : "Show inspector")
        }
    }
}

private struct SidebarView: View {
    @Bindable var model: AppModel
    @Binding var search: String

    var body: some View {
        ScriptBrowser(nodes: model.fileTree, folder: model.settings.folder, query: search,
                      sortOrder: model.settings.fileSortOrder, selectedURL: model.selectedURL, openFile: model.openFile)
            .overlay { emptyState }
            .safeAreaInset(edge: .top, spacing: 0) {
                SidebarSearchField(text: $search, prompt: "Find a script")
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.scanning && ScriptTreeNode.filter(model.fileTree, query: search).isEmpty {
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView {
                    Label("No Scripts", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("This folder doesn’t contain any Markdown files.")
                } actions: {
                    Button("Choose Folder…", action: model.chooseFolder)
                }
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Choose Folder…", action: model.chooseFolder)
                Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: model.settings.folder)) }
                Divider()
                Button("Refresh", action: model.scanFolder)
            } label: {
                Label(URL(fileURLWithPath: model.settings.folder).lastPathComponent, systemImage: "folder")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .help("\(model.settings.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))\nCue reads your original files. It never copies or edits them.")

            Spacer(minLength: 0)
            if model.scanning { ProgressView().controlSize(.small) }

            Menu {
                Picker("Sort By", selection: $model.settings.fileSortOrder) {
                    ForEach(FileSortOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .labelStyle(.iconOnly)
            .fixedSize()
            .help("Sort: \(model.settings.fileSortOrder.title). Folders stay first.")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private extension View {
    @ViewBuilder func prominentButtonStyle() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }
}
