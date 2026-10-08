import AppKit
import SwiftUI
import Carbon

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Cue", id: "main") {
            ContentView(model: delegate.model)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { CueCommands(model: delegate.model) }

        // Qualified because the app's own `Settings` model shadows SwiftUI's scene.
        SwiftUI.Settings {
            SettingsView(model: delegate.model)
        }

        MenuBarExtra("Cue", systemImage: "text.viewfinder") {
            StatusMenu(model: delegate.model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x43554531

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotkeys()
        for argument in CommandLine.arguments.dropFirst() where ["md", "markdown"].contains(URL(fileURLWithPath: argument).pathExtension) { model.openFile(URL(fileURLWithPath: argument)) }
    }
    func registerHotkeys() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == AppDelegate.signature else { return OSStatus(eventNotHandledErr) }
            let model = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().model
            switch id.id { case 1: model.togglePlayback(); case 2: model.toggleProjection(); case 3: model.toggleBlackout(); case 4: model.rewind(); default: break }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        for (index, key) in [kVK_Space, kVK_ANSI_P, kVK_ANSI_B, kVK_ANSI_R].enumerated() {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: Self.signature, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { hotkeys.append(ref) } else { model.error = "A global shortcut is already in use. Cue’s window and menu-bar controls still work." }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) { if let url = urls.first { model.openFile(url) } }
    // Cue keeps running in the menu bar after its window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown(); for key in hotkeys { UnregisterEventHotKey(key) }; if let eventHandler { RemoveEventHandler(eventHandler) } }
}

/// Global hotkeys consume these key combinations first; the menu shows them and covers any that failed to register.
struct CueCommands: Commands {
    let model: AppModel
    private let hyper: SwiftUI.EventModifiers = [.control, .option, .command]

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Cue") {
                NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: "Native Markdown prompting. Your files, your pace.")])
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Script…", action: model.chooseFile).keyboardShortcut("o")
            Button("Choose Scripts Folder…", action: model.chooseFolder).keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Show Script in Finder", action: model.revealCurrentFile)
            Button("Refresh Scripts", action: model.scanFolder).keyboardShortcut("r")
        }
        CommandGroup(after: .textEditing) {
            Button("Find Script") { NotificationCenter.default.post(name: SidebarSearchField.focusRequest, object: nil) }
                .keyboardShortcut("f")
        }
        SidebarCommands()
        InspectorCommands()
        CommandMenu("Playback") {
            Button("Play / Pause", action: model.togglePlayback).keyboardShortcut(.space, modifiers: hyper)
            Button("Back to Start", action: model.rewind).keyboardShortcut("r", modifiers: hyper)
            Divider()
            Button("Project / Stop Projection", action: model.toggleProjection).keyboardShortcut("p", modifiers: hyper)
            Button("Blackout / Show Script", action: model.toggleBlackout).keyboardShortcut("b", modifiers: hyper)
        }
    }
}

struct StatusMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Cue") { openWindow(id: "main"); NSApp.activate() }
        Divider()
        Button(model.isPlaying ? "Pause" : "Play", action: model.togglePlayback).disabled(model.blocks.isEmpty)
        Button("Back to Start", action: model.rewind).disabled(model.blocks.isEmpty)
        Divider()
        Button(model.isProjecting ? "Stop Projection" : "Project to Display", action: model.toggleProjection)
            .disabled(!model.isProjecting && model.blocks.isEmpty)
        Button(model.blanked ? "Show Script" : "Blackout", action: model.toggleBlackout).disabled(!model.isProjecting)
        Divider()
        Button("Quit Cue") { NSApp.terminate(nil) }
    }
}
