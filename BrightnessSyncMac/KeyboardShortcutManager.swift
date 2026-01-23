import Cocoa
import Carbon.HIToolbox

/// Manages global keyboard shortcuts for brightness control
class KeyboardShortcutManager {
    
    weak var delegate: BrightnessChangeDelegate?
    var brightnessController: BrightnessController?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Shortcut configuration
    private let brightnessStep: Float = 0.0625 // 6.25% per step
    
    // Default shortcuts: Ctrl+Shift+Up/Down
    private let modifierFlags: CGEventFlags = [.maskControl, .maskShift]
    private let upKeyCode: CGKeyCode = 126    // Up arrow
    private let downKeyCode: CGKeyCode = 125  // Down arrow
    
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
            print("BrightnessSync: Failed to create keyboard shortcut tap")
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        print("BrightnessSync: Keyboard shortcuts active (Ctrl+Shift+↑/↓)")
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
        // Re-enable if disabled
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Check for Ctrl+Shift modifier
        let hasCtrl = flags.contains(.maskControl)
        let hasShift = flags.contains(.maskShift)
        let hasCmd = flags.contains(.maskCommand)
        let hasOpt = flags.contains(.maskAlternate)
        
        // Must have Ctrl+Shift, no Cmd or Option
        guard hasCtrl && hasShift && !hasCmd && !hasOpt else {
            return Unmanaged.passUnretained(event)
        }
        
        // Check for up/down arrow
        if keyCode == upKeyCode || keyCode == downKeyCode {
            let isUp = keyCode == upKeyCode
            
            DispatchQueue.main.async { [weak self] in
                self?.adjustBrightness(up: isUp)
            }
            
            // Consume the event
            return nil
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func adjustBrightness(up: Bool) {
        guard let controller = brightnessController else { return }
        
        let current = controller.getBrightness()
        let newLevel = up ? min(1.0, current + brightnessStep) : max(0.0, current - brightnessStep)
        
        print("BrightnessSync: Shortcut \(up ? "↑" : "↓") → \(Int(newLevel * 100))%")
        controller.setBrightness(newLevel)
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.brightnessDidChange(sliderValue: newLevel)
        }
    }
}
