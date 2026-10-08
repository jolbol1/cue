import AppKit
import IOKit.hid
import PrompterCore

final class PedalController {
    unowned let model: AppModel
    private var manager: IOHIDManager?
    private var connected = Set<UInt>()
    init(model: AppModel) { self.model = model }
    func start() {
        stop()
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = hid
        IOHIDManagerSetDeviceMatching(hid, [kIOHIDVendorIDKey: 0x0fd9, kIOHIDProductIDKey: 0x0086] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hid, { ctx, result, _, device in
            guard let ctx else { return }; let owner = Unmanaged<PedalController>.fromOpaque(ctx).takeUnretainedValue()
            if result == kIOReturnSuccess { owner.connected.insert(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())); owner.model.pedalStatus = "Stream Deck Pedal connected • press a pedal to test" }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hid, { ctx, _, _, device in
            guard let ctx else { return }; let owner = Unmanaged<PedalController>.fromOpaque(ctx).takeUnretainedValue()
            owner.connected.remove(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
            owner.model.pedalKeys = [false, false, false]
            owner.model.pedalStatus = "Pedal disconnected • reconnect USB to resume"
        }, context)
        IOHIDManagerRegisterInputReportCallback(hid, { ctx, result, _, type, _, bytes, length in
            guard let ctx, result == kIOReturnSuccess, type == kIOHIDReportTypeInput else { return }
            let owner = Unmanaged<PedalController>.fromOpaque(ctx).takeUnretainedValue()
            guard let keys = PedalReport.decode(Array(UnsafeBufferPointer(start: bytes, count: length))) else { return }
            let old = owner.model.pedalKeys
            owner.model.pedalKeys = keys
            owner.model.pedalStatus = "Stream Deck Pedal • receiving input"
            if keys[1] && !old[1] { owner.model.togglePlayback() }
        }, context)
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess { model.pedalStatus = "Looking for Stream Deck Pedal…" }
        else { model.pedalStatus = "Pedal access unavailable (\(result)). Check Input Monitoring, then reconnect." }
    }
    func stop() {
        if let manager {
            IOHIDManagerRegisterInputReportCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil; connected.removeAll(); model.pedalKeys = [false, false, false]; model.pedalStatus = "Direct pedal input is off"
    }
}
