import Cocoa
import Carbon.HIToolbox

/// Manages global keyboard shortcuts for brightness control
class KeyboardShortcutManager {
    
    weak var delegate: BrightnessChangeDelegate?
    var brightnessController: BrightnessController?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Brightness step
    private let brightnessStep: Float = 0.0625
    
    // Key codes - using [ and ] which exist on all keyboards
    private let brightnessUpKeyCode: UInt16 = 30    // ] key
    private let brightnessDownKeyCode: UInt16 = 33  // [ key
    
    // Also support arrow keys as alternative
    private let upArrowKeyCode: UInt16 = 126
    private let downArrowKeyCode: UInt16 = 125
    
    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let ref = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(ref).takeUnretainedValue()
                return manager.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("BrightnessSync: ❌ Failed to create event tap - check Accessibility permissions")
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        print("BrightnessSync: ✓ Keyboard shortcuts active")
        print("BrightnessSync:   Option+] = Brightness Up")
        print("BrightnessSync:   Option+[ = Brightness Down")
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
    }
    
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it was disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Check for Option modifier only (no Cmd, no Ctrl, no Shift)
        let hasOption = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        
        // Require Option only
        guard hasOption && !hasShift && !hasCmd && !hasCtrl else {
            return Unmanaged.passUnretained(event)
        }
        
        // Check for our brightness keys: [ and ] or arrow keys
        var isBrightnessUp = false
        var isBrightnessDown = false
        
        if keyCode == brightnessUpKeyCode || keyCode == upArrowKeyCode {
            isBrightnessUp = true
        } else if keyCode == brightnessDownKeyCode || keyCode == downArrowKeyCode {
            isBrightnessDown = true
        }
        
        if isBrightnessUp || isBrightnessDown {
            print("BrightnessSync: Shortcut detected - \(isBrightnessUp ? "UP" : "DOWN")")
            
            DispatchQueue.main.async { [weak self] in
                self?.adjustBrightness(up: isBrightnessUp)
            }
            
            // Consume the event so it doesn't do anything else
            return nil
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func adjustBrightness(up: Bool) {
        guard let controller = brightnessController else {
            print("BrightnessSync: No controller")
            return
        }
        
        let current = controller.getBrightness()
        let newLevel = up ? min(1.0, current + brightnessStep) : max(0.0, current - brightnessStep)
        
        print("BrightnessSync: \(up ? "↑" : "↓") → \(Int(newLevel * 100))%")
        controller.setBrightness(newLevel)
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.brightnessDidChange(sliderValue: newLevel)
        }
    }
}
