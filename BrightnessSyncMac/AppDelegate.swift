import Cocoa
import Carbon.HIToolbox
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate, MediaKeyDelegate {
    
    private var statusItem: NSStatusItem!
    private var brightnessController: BrightnessController!
    private var sliderView: BrightnessSliderView!
    private var mediaKeyManager: MediaKeyManager!
    
    // Brightness step (10% normally, 2.5% with Shift+Option like native macOS)
    private let brightnessStep: Float = 0.0625 // 1/16th like native macOS
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("BrightnessSync: App launching...")
        
        // Initialize brightness controller
        brightnessController = BrightnessController()
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                button.image = image
                button.image?.isTemplate = true
            } else {
                button.title = "☀️"
            }
        }
        
        // Create menu
        setupMenu()
        
        // Initialize Media Key Manager
        mediaKeyManager = MediaKeyManager()
        mediaKeyManager.delegate = self
        
        // Check permissions and start
        checkAccessibilityPermissions()
        
        // Monitor for display changes (plug/unplug)
        monitorDisplayChanges()
        
        print("BrightnessSync: Ready!")
    }
    
    private func monitorDisplayChanges() {
        CGDisplayRegisterReconfigurationCallback({ (displayId, flags, userInfo) in
            guard let userInfo = userInfo else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            
            if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) {
                print("BrightnessSync: Display configuration changed")
                DispatchQueue.main.async {
                    delegate.handleDisplayChange()
                }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    func handleDisplayChange() {
        // Refresh display list and update CLI/UI
        print("BrightnessSync: Refreshing displays...")
        if let menu = statusItem.menu,
           let infoItem = menu.items.first(where: { $0.title.contains("display") }) {
            let displayCount = brightnessController.getDisplayCount()
            infoItem.title = "\(displayCount) display(s) connected"
        }
        
        // Re-apply current brightness to ensure new monitors get synced immediately
        let current = brightnessController.getBrightness()
        brightnessController.setBrightness(current)
    }
    
    // MARK: - Accessibility Permissions
    
    private func checkAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        
        if trusted {
            print("BrightnessSync: Accessibility access granted ✓")
            mediaKeyManager.start()
        } else {
            print("BrightnessSync: Requesting accessibility access...")
            promptForAccessibility()
        }
    }
    
    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if accessEnabled {
            mediaKeyManager.start()
        } else {
            showAccessibilityAlert()
            startAccessibilityPolling()
        }
    }
    
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "BrightnessSync needs Accessibility access to detect native brightness keys (F1/F2) and suppress system defaults.\n\nPlease enable it in System Settings → Privacy & Security → Accessibility."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func startAccessibilityPolling() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                print("BrightnessSync: Accessibility access granted ✓")
                DispatchQueue.main.async {
                    self?.mediaKeyManager.start()
                    self?.updateMenuWithShortcutStatus(enabled: true)
                }
            }
        }
    }
    
    private func updateMenuWithShortcutStatus(enabled: Bool) {
        if let menu = statusItem.menu,
           let shortcutItem = menu.items.first(where: { $0.title.contains("Native") || $0.title.contains("keys") }) {
            shortcutItem.title = enabled ? "Native F1/F2 keys active ✓" : "Native keys (needs permissions)"
        }
    }
    
    // MARK: - MediaKeyDelegate
    
    func handleBrightnessEvent(up: Bool, isRepeat: Bool) {
        let current = brightnessController.getBrightness()
        
        // Shift+Option+F1/F2 usually does smaller steps, simple F1/F2 does standard
        // For now using 6.25% (1/16) which is standard macOS step
        let step = brightnessStep
        
        let newLevel = up ? min(1.0, current + step) : max(0.0, current - step)
        
        brightnessController.setBrightness(newLevel)
        sliderView.updateSlider()
        showBrightnessOSD(level: newLevel)
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let headerItem = NSMenuItem(title: "BrightnessSync Mac", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        let sliderItem = NSMenuItem()
        sliderView = BrightnessSliderView(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        sliderView.brightnessController = brightnessController
        sliderView.updateSlider()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        menu.addItem(NSMenuItem.separator())
        
        let shortcutStatus = AXIsProcessTrusted() ? "Native F1/F2 keys active ✓" : "Native keys (needs permissions)"
        let shortcutInfo = NSMenuItem(title: shortcutStatus, action: nil, keyEquivalent: "")
        shortcutInfo.isEnabled = false
        menu.addItem(shortcutInfo)
        
        let displayCount = brightnessController.getDisplayCount()
        let infoItem = NSMenuItem(title: "\(displayCount) display(s) connected", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit BrightnessSync", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        menu.delegate = self
    }
    
    private func showBrightnessOSD(level: Float) {
        if let button = statusItem.button {
            let percentage = Int(level * 100)
            button.title = "\(percentage)%"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                    button.title = ""
                    button.image = image
                    button.image?.isTemplate = true
                } else {
                    button.title = "☀️"
                }
            }
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        sliderView.updateSlider()
        if let infoItem = menu.items.first(where: { $0.title.contains("display") }) {
            let displayCount = brightnessController.getDisplayCount()
            infoItem.title = "\(displayCount) display(s) connected"
        }
    }
}

// Slider View Implementation
class BrightnessSliderView: NSView {
    
    var brightnessController: BrightnessController?
    
    private let slider: NSSlider = {
        let slider = NSSlider()
        slider.minValue = 0
        slider.maxValue = 100
        slider.sliderType = .linear
        slider.isContinuous = true
        return slider
    }()
    
    private let percentageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "100%")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) { super.init(coder: coder); setupViews() }
    
    private func setupViews() {
        let iconSize: CGFloat = 16
        let padding: CGFloat = 12
        let spacing: CGFloat = 8
        let labelWidth: CGFloat = 36
        
        let lowIcon = NSTextField(labelWithString: "🔅")
        lowIcon.font = .systemFont(ofSize: 12)
        lowIcon.frame = NSRect(x: padding, y: (bounds.height - iconSize)/2, width: iconSize, height: iconSize)
        addSubview(lowIcon)
        
        let sliderX = padding + iconSize + spacing
        let sliderWidth = bounds.width - sliderX - spacing - iconSize - spacing - labelWidth - padding
        slider.frame = NSRect(x: sliderX, y: (bounds.height - 21)/2, width: sliderWidth, height: 21)
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        addSubview(slider)
        
        let highIcon = NSTextField(labelWithString: "🔆")
        highIcon.font = .systemFont(ofSize: 12)
        highIcon.frame = NSRect(x: sliderX + sliderWidth + spacing, y: (bounds.height - iconSize)/2, width: iconSize, height: iconSize)
        addSubview(highIcon)
        
        percentageLabel.frame = NSRect(x: highIcon.frame.maxX + spacing, y: (bounds.height - 16)/2, width: labelWidth, height: 16)
        addSubview(percentageLabel)
    }
    
    func updateSlider() {
        let brightness = brightnessController?.getBrightness() ?? 0.5
        slider.doubleValue = Double(brightness * 100)
        percentageLabel.stringValue = "\(Int(brightness * 100))%"
    }
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue / 100.0)
        brightnessController?.setBrightness(value)
        percentageLabel.stringValue = "\(Int(sender.doubleValue))%"
    }
}
