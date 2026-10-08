import AppKit
import Observation
import PrompterCore

@Observable
final class AppModel {
    var settings: Settings { didSet { saveSettings(); if oldValue.mode != settings.mode { pause() }; if oldValue.includeCode != settings.includeCode { parseScript() } } }
    var fileTree: [ScriptTreeNode] = []
    var selectedURL: URL?
    var blocks: [ScriptBlock] = []
    var fileStatus = ""
    var error: String?
    var isPlaying = false
    var countdownRemaining = 0
    var progress = 0.0
    var screens: [NSScreen] = []
    var isProjecting = false
    var blanked = false
    var pedalStatus = "Direct pedal input is off"
    var pedalKeys = [false, false, false]
    var scanning = false
    var canvasSize = CGSize(width: 1024, height: 600)
    var maximum = 1.0
    // The canvases poll these every frame; tracking them would re-render SwiftUI at 60 Hz.
    @ObservationIgnored var source = ""
    @ObservationIgnored var position = 0.0
    @ObservationIgnored let layout = ScriptLayout()
    @ObservationIgnored private var fileSignature: String?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var watcher: Timer?
    @ObservationIgnored private var lastTick = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var lastProgress = 0.0
    @ObservationIgnored private var startDeadline: Double?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored lazy var output = OutputController(model: self)
    @ObservationIgnored lazy var pedal = PedalController(model: self)

    init() {
        if let data = UserDefaults.standard.data(forKey: "Cue.Settings"), let saved = try? JSONDecoder().decode(Settings.self, from: data) { settings = saved } else { settings = Settings() }
        refreshScreens()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshScreens() }
        scanFolder()
        if !settings.lastFile.isEmpty { openFile(URL(fileURLWithPath: settings.lastFile)) }
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        watcher = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.reloadIfChanged() }
        RunLoop.main.add(watcher!, forMode: .common)
        if settings.pedalEnabled { pedal.start() }
    }

    func saveSettings() {
        saveWork?.cancel()
        let snapshot = settings
        let work = DispatchWorkItem { if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: "Cue.Settings") } }
        saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func refreshScreens() {
        screens = NSScreen.screens
        if !screens.contains(where: { $0.displayID == settings.displayID }) {
            if isProjecting { stopProjection(); error = "The output display disconnected. Projection has stopped." }
            settings.displayID = screens.first(where: { $0.localizedName.localizedCaseInsensitiveContains("elgato") || $0.localizedName.localizedCaseInsensitiveContains("prompter") })?.displayID ?? screens.first(where: { $0 != NSScreen.main })?.displayID ?? screens.first?.displayID ?? 0
        }
        updateCanvas()
        if isProjecting { output.show() }
    }
    var selectedScreen: NSScreen? { screens.first { $0.displayID == settings.displayID } }
    func updateCanvas() {
        let size = selectedScreen?.frame.size ?? CGSize(width: 1024, height: 600)
        if size != canvasSize { canvasSize = size }
        rebuildLayout()
    }
    func rebuildLayout() {
        layout.build(blocks: blocks, settings: settings, size: canvasSize)
        let limit = max(0, layout.height - 1)
        if limit != maximum { maximum = limit }
        position = min(position, maximum)
    }
    /// Heading titles in script order, without inline Markdown.
    var headings: [String] {
        blocks.compactMap { block in
            guard case .heading = block.kind else { return nil }
            return (try? AttributedString(markdown: block.text)).map { String($0.characters) } ?? block.text
        }
    }
    func jumpToHeading(_ index: Int) {
        rebuildLayout()
        guard layout.headings.indices.contains(index) else { return }
        pause(); position = layout.headings[index].y
    }
    /// Estimated reading time left at the constant playback speed.
    var remainingSeconds: Double { (1 - progress) * maximum / max(1, settings.speed) }
    private func present(_ panel: NSOpenPanel, then completion: @escaping (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in if response == .OK, let url = panel.url { completion(url) } }
        if let window = NSApp.mainWindow { panel.beginSheetModal(for: window, completionHandler: handler) } else { handler(panel.runModal()) }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: settings.folder); panel.prompt = "Use Folder"
        panel.message = "Choose the folder that contains your scripts. Cue only reads these files."
        present(panel) { [weak self] url in self?.settings.folder = url.path; self?.scanFolder() }
    }
    func chooseFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, .text]; panel.allowsOtherFileTypes = true
        panel.directoryURL = URL(fileURLWithPath: settings.folder)
        present(panel) { [weak self] url in self?.openFile(url) }
    }
    func revealCurrentFile() {
        if let selectedURL { NSWorkspace.shared.activateFileViewerSelecting([selectedURL]) }
    }
    func scanFolder() {
        let path = settings.folder; scanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // The enumerator reports fully resolved paths (/tmp becomes /private/tmp), so resolve the root
            // the same way. `resolvingSymlinksInPath()` deliberately strips /private, so use realpath.
            let resolved = realpath(path, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) }
            let root = URL(fileURLWithPath: resolved ?? path)
            var result: [String] = []
            var dates: [String: ScriptFileDates] = [:]
            var scanError: String?
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .creationDateKey]
            if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in scanError = error.localizedDescription; return true }) {
                for case let url as URL in walker {
                    if ["node_modules", ".git"].contains(url.lastPathComponent) { walker.skipDescendants(); continue }
                    let values = try? url.resourceValues(forKeys: keys)
                    let relativePath = String(url.path.dropFirst(root.path.count + 1))
                    let markdown = ["md", "markdown"].contains(url.pathExtension.lowercased()) && values?.isRegularFile == true
                    if values?.isDirectory == true || markdown {
                        dates[relativePath] = ScriptFileDates(modified: values?.contentModificationDate, created: values?.creationDate)
                    }
                    if markdown { result.append(relativePath) }
                }
            } else { scanError = "Couldn’t read the folder. Choose an existing scripts folder." }
            let found = ScriptTreeNode.build(paths: result, dates: dates); let issue = scanError
            DispatchQueue.main.async {
                guard let self, self.settings.folder == path else { return }
                self.fileTree = found; self.scanning = false
                if let issue { self.error = issue }
            }
        }
    }
    func openFile(_ url: URL) {
        guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else { error = "Choose a .md or .markdown file."; return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            pause(); selectedURL = url; settings.lastFile = url.path; source = text
            position = 0; parseScript(); fileSignature = signature(url)
            fileStatus = "Up to date"
        } catch { self.error = "Couldn’t open \(url.lastPathComponent): \(error.localizedDescription)" }
    }
    func parseScript() { blocks = MarkdownScript.parse(source, includeCode: settings.includeCode); rebuildLayout() }
    private func signature(_ url: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return "\(a[.modificationDate] ?? "")-\(a[.size] ?? "")-\(a[.systemFileNumber] ?? "")"
    }
    func reloadIfChanged() {
        guard let url = selectedURL else { return }
        guard let current = signature(url) else { fileStatus = "File unavailable — showing last readable version"; return }
        guard current != fileSignature else { return }
        do {
            let updated = try String(contentsOf: url, encoding: .utf8)
            let oldProgress = position / max(1, maximum)
            source = updated; parseScript(); position = oldProgress * maximum
            fileSignature = current; fileStatus = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
        } catch { fileStatus = "Couldn’t reload — showing last readable version" }
    }
    func togglePlayback() {
        if isPlaying || startDeadline != nil { pause(); return }
        guard !blocks.isEmpty else { return }
        if position >= maximum { position = 0 }
        if settings.countdown > 0 { startDeadline = ProcessInfo.processInfo.systemUptime + Double(settings.countdown); countdownRemaining = settings.countdown }
        else { beginPlayback() }
    }
    private func beginPlayback() {
        startDeadline = nil; countdownRemaining = 0; isPlaying = true
        if activity == nil { activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Reading a teleprompter script") }
    }
    func pause() {
        startDeadline = nil
        if countdownRemaining != 0 { countdownRemaining = 0 }
        if isPlaying { isPlaying = false }
        if let activity, !isProjecting { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    func rewind() { pause(); position = 0; progress = 0 }
    func seek(_ fraction: Double) { position = min(max(0, fraction), 1) * maximum }
    func nudge(_ delta: Double) { position = min(max(0, position + delta), maximum) }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime; let dt = min(0.1, now - lastTick); lastTick = now
        if let deadline = startDeadline {
            let remaining = max(0, Int(ceil(deadline - now)))
            if remaining != countdownRemaining { countdownRemaining = remaining }
            if now >= deadline { beginPlayback() }
        }
        let pedalDirection = settings.pedalEnabled ? (pedalKeys[2] ? 1.0 : 0) - (pedalKeys[0] ? 1.0 : 0) : 0
        if pedalDirection != 0 {
            position = ScrollMath.advance(position: position, velocity: pedalDirection * settings.pedalSpeed, elapsed: dt, maximum: maximum, loop: false)
        } else if isPlaying {
            position = ScrollMath.advance(position: position, velocity: settings.speed, elapsed: dt, maximum: maximum, loop: settings.loop)
            if position >= maximum && !settings.loop { pause() }
        }
        if now - lastProgress > 0.1 { let next = position / max(1, maximum); if next != progress { progress = next }; lastProgress = now }
    }
    func startProjection() {
        guard !blocks.isEmpty, selectedScreen != nil else { return }
        updateCanvas(); output.show(); isProjecting = true
        if activity == nil { activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Displaying a teleprompter script") }
    }
    func stopProjection() { output.hide(); isProjecting = false; blanked = false; pause() }
    func toggleProjection() { isProjecting ? stopProjection() : startProjection() }
    /// Blackout only applies to live output, so it can't silently carry into the next projection.
    func toggleBlackout() { if isProjecting { blanked.toggle() } }
    func setPedalEnabled(_ enabled: Bool) { settings.pedalEnabled = enabled; enabled ? pedal.start() : pedal.stop() }
    func shutdown() { isProjecting = false; pause(); pedal.stop(); timer?.invalidate(); watcher?.invalidate(); output.hide() }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
