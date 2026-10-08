import AppKit
import Carbon

/// The output never takes focus. Reserve Escape only while the pointer is over it.
final class ProjectionEscapeShortcut {
    private var frame: NSRect?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var mouseMonitor: Any?
    private var timer: Timer?
    private var wasOverOutput = false
    private let onEscape: () -> Void
    private let onFailure: () -> Void
    private static let signature: OSType = 0x43554545

    init(onEscape: @escaping () -> Void, onFailure: @escaping () -> Void) {
        self.onEscape = onEscape
        self.onFailure = onFailure
    }

    func start(frame: NSRect) {
        self.frame = frame
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr, id.signature == ProjectionEscapeShortcut.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<ProjectionEscapeShortcut>.fromOpaque(context).takeUnretainedValue()
                if owner.pointerIsOverOutput { owner.onEscape() }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            if result != noErr { onFailure() }
        }
        if localMonitor == nil {
            let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in self?.updateRegistration() }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents.union(.keyDown)) { [weak self] event in
                guard let self else { return event }
                self.updateRegistration()
                if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape),
                   event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                   self.pointerIsOverOutput {
                    self.onEscape()
                    return nil
                }
                return event
            }
            // Also handle cursor warps and display changes that generate no mouse event.
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateRegistration() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        updateRegistration()
    }

    private var pointerIsOverOutput: Bool { frame?.contains(NSEvent.mouseLocation) == true }

    private func updateRegistration() {
        let isOverOutput = pointerIsOverOutput
        guard isOverOutput != wasOverOutput else { return }
        wasOverOutput = isOverOutput
        if isOverOutput, handler != nil {
            let result = RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(), 0, &hotkey)
            if result != noErr { onFailure() }
        } else if let hotkey {
            UnregisterEventHotKey(hotkey)
            self.hotkey = nil
        }
    }

    func stop() {
        frame = nil
        updateRegistration()
        timer?.invalidate(); timer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }; mouseMonitor = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }

    deinit { stop() }
}
