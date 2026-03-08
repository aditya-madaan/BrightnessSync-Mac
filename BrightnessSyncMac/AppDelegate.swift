import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Design Tokens
private enum DS {
    // Colors
    static let amber     = NSColor(red: 0.957, green: 0.753, blue: 0.145, alpha: 1) // #f4c025
    static let amberDim  = NSColor(red: 0.957, green: 0.753, blue: 0.145, alpha: 0.15)
    static let surface   = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)    // #1c1c1f
    static let surface2  = NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)    // #292930
    static let border    = NSColor(white: 1.0, alpha: 0.08)
    static let text      = NSColor(white: 1.0, alpha: 0.92)
    static let textMuted = NSColor(white: 1.0, alpha: 0.45)
    static let green     = NSColor(red: 0.20, green: 0.87, blue: 0.50, alpha: 1)
    static let separator = NSColor(white: 1.0, alpha: 0.10)

    // Sizing
    static let popoverWidth: CGFloat  = 280
    static let popoverHeight: CGFloat = 230
    static let cornerRadius: CGFloat  = 12
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, BrightnessChangeDelegate {

    private var statusItem: NSStatusItem!
    private var brightnessController: BrightnessController!
    private var popoverView: ModernPopoverView!
    private var settingsWindow: NSWindow?
    private var shortcutManager: KeyboardShortcutManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("BrightnessSync: App launching...")

        brightnessController = BrightnessController()
        brightnessController.delegate = self

        shortcutManager = KeyboardShortcutManager()
        shortcutManager.brightnessController = brightnessController
        shortcutManager.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                button.image = image
                button.image?.isTemplate = true
            } else {
                button.title = "☀️"
            }
        }

        setupMenu()
        monitorDisplayChanges()
        brightnessController.startMonitoring()
        checkAccessibilityPermissions()

        print("BrightnessSync: Ready!")
    }

    func applicationWillTerminate(_ notification: Notification) {
        brightnessController.stopMonitoring()
        shortcutManager.stop()
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermissions() {
        if AXIsProcessTrusted() {
            print("BrightnessSync: Accessibility ✓")
            shortcutManager.start()
        } else {
            promptForAccessibility()
        }
    }

    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        if accessEnabled {
            shortcutManager.start()
        } else {
            showAccessibilityAlert()
            startAccessibilityPolling()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "BrightnessSync needs Accessibility access for keyboard shortcuts (Option+[ / ]).\n\nPlease enable in System Settings → Privacy & Security → Accessibility."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func startAccessibilityPolling() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.shortcutManager.start()
                self?.popoverView?.updateShortcutStatus(active: true)
            }
        }
    }

    // MARK: - BrightnessChangeDelegate

    func brightnessDidChange(sliderValue: Float) {
        popoverView?.updateSlider()
    }

    private func monitorDisplayChanges() {
        CGDisplayRegisterReconfigurationCallback({ (displayId, flags, userInfo) in
            guard let userInfo = userInfo else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) {
                DispatchQueue.main.async { delegate.handleDisplayChange() }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func handleDisplayChange() {
        print("BrightnessSync: Display changed, syncing...")
        let displayCount = brightnessController.getDisplayCount()
        popoverView?.updateDisplayCount(displayCount)
        let current = brightnessController.getBrightness()
        brightnessController.setBrightness(current)
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        let menu = NSMenu()

        // Modern popover panel item
        let popoverItem = NSMenuItem()
        popoverView = ModernPopoverView(frame: NSRect(x: 0, y: 0, width: DS.popoverWidth, height: DS.popoverHeight))
        popoverView.brightnessController = brightnessController
        popoverView.onOpenSettings = { [weak self] in self?.openSettings() }
        popoverView.onQuit = { NSApp.terminate(nil) }
        popoverView.updateSlider()
        popoverView.updateShortcutStatus(active: AXIsProcessTrusted())
        popoverView.updateDisplayCount(brightnessController.getDisplayCount())
        popoverItem.view = popoverView
        menu.addItem(popoverItem)

        statusItem.menu = menu
        menu.delegate = self
    }

    @objc private func openSettings() {
        if settingsWindow == nil { createSettingsWindow() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings Window

    private func createSettingsWindow() {
        let windowWidth: CGFloat  = 380
        let windowHeight: CGFloat = 270

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Calibration Settings"
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = DS.surface

        let contentView = ModernSettingsView(
            frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            brightnessController: brightnessController
        )
        window.contentView = contentView
        settingsWindow = window
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        popoverView?.updateSlider()
        popoverView?.updateDisplayCount(brightnessController.getDisplayCount())
        popoverView?.updateShortcutStatus(active: AXIsProcessTrusted())
    }
}

// MARK: - ModernPopoverView

class ModernPopoverView: NSView {

    var brightnessController: BrightnessController?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    // Sub-views
    private let gradientSlider   = AmberGradientSlider()
    private let percentLabel     = NSTextField(labelWithString: "50%")
    private let syncBadge        = StatusBadge()
    private let shortcutBadge    = StatusBadge()
    private let displayBadge     = StatusBadge()
    private let settingsButton   = HoverMenuItem()
    private let quitButton       = HoverMenuItem()

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = DS.surface.cgColor
        layer?.cornerRadius    = DS.cornerRadius

        // ── Header ──────────────────────────────────────────────
        let sunIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            sunIcon.image = img.withSymbolConfiguration(config)
        }
        sunIcon.contentTintColor = DS.amber
        sunIcon.frame = NSRect(x: 18, y: 196, width: 20, height: 20)
        addSubview(sunIcon)

        let titleLabel = NSTextField(labelWithString: "BrightnessSync")
        titleLabel.font      = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = DS.text
        titleLabel.frame     = NSRect(x: 43, y: 197, width: 180, height: 18)
        addSubview(titleLabel)

        // Thin separator
        let sep1 = NSBox()
        sep1.boxType    = .separator
        sep1.frame      = NSRect(x: 0, y: 188, width: DS.popoverWidth, height: 1)
        sep1.borderColor = DS.separator
        addSubview(sep1)

        // ── Brightness label + percentage ─────────────────────
        let bLabel = NSTextField(labelWithString: "BRIGHTNESS")
        bLabel.font      = .systemFont(ofSize: 9, weight: .semibold)
        bLabel.textColor = DS.textMuted
        bLabel.frame     = NSRect(x: 18, y: 165, width: 100, height: 14)
        addSubview(bLabel)

        percentLabel.font      = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        percentLabel.textColor = DS.amber
        percentLabel.alignment = .right
        percentLabel.frame     = NSRect(x: DS.popoverWidth - 64, y: 163, width: 46, height: 18)
        addSubview(percentLabel)

        // ── Amber gradient slider ─────────────────────────────
        gradientSlider.frame  = NSRect(x: 18, y: 138, width: DS.popoverWidth - 36, height: 22)
        gradientSlider.onValueChanged = { [weak self] val in
            self?.brightnessController?.setBrightness(Float(val / 100.0))
            self?.percentLabel.stringValue = "\(Int(val))%"
        }
        addSubview(gradientSlider)

        // ── Status badges ─────────────────────────────────────
        let sep2 = NSBox()
        sep2.boxType     = .separator
        sep2.frame       = NSRect(x: 0, y: 127, width: DS.popoverWidth, height: 1)
        sep2.borderColor = DS.separator
        addSubview(sep2)

        syncBadge.configure(icon: "arrow.triangle.2.circlepath", text: "Syncing with F1 / F2", dotColor: DS.green)
        syncBadge.frame = NSRect(x: 14, y: 97, width: DS.popoverWidth - 28, height: 24)
        addSubview(syncBadge)

        shortcutBadge.configure(icon: "keyboard", text: "⌥[ / ] shortcuts active", dotColor: DS.amber)
        shortcutBadge.frame = NSRect(x: 14, y: 71, width: DS.popoverWidth - 28, height: 24)
        addSubview(shortcutBadge)

        displayBadge.configure(icon: "display", text: "1 display connected", dotColor: DS.textMuted)
        displayBadge.frame = NSRect(x: 14, y: 45, width: DS.popoverWidth - 28, height: 24)
        addSubview(displayBadge)

        // ── Bottom separator ──────────────────────────────────
        let sep3 = NSBox()
        sep3.boxType     = .separator
        sep3.frame       = NSRect(x: 0, y: 36, width: DS.popoverWidth, height: 1)
        sep3.borderColor = DS.separator
        addSubview(sep3)

        // ── Menu items: Settings + Quit ───────────────────────
        settingsButton.configure(title: "Calibration Settings...", keyEquiv: "⌘,")
        settingsButton.frame   = NSRect(x: 0, y: 18, width: DS.popoverWidth, height: 20)
        settingsButton.onTap   = { [weak self] in self?.onOpenSettings?() }
        addSubview(settingsButton)

        quitButton.configure(title: "Quit BrightnessSync", keyEquiv: "⌘Q")
        quitButton.frame = NSRect(x: 0, y: 0, width: DS.popoverWidth, height: 20)
        quitButton.onTap = { [weak self] in self?.onQuit?() }
        addSubview(quitButton)
    }

    func updateSlider() {
        let b = brightnessController?.getBrightness() ?? 0.5
        gradientSlider.setValue(Double(b * 100))
        percentLabel.stringValue = "\(Int(b * 100))%"
    }

    func updateShortcutStatus(active: Bool) {
        shortcutBadge.setDotColor(active ? DS.amber : DS.textMuted)
        shortcutBadge.setText(active ? "⌥[ / ] shortcuts active" : "⌥[ / ] (needs permissions)")
    }

    func updateDisplayCount(_ count: Int) {
        displayBadge.setText("\(count) display\(count == 1 ? "" : "s") connected")
    }
}

// MARK: - AmberGradientSlider

class AmberGradientSlider: NSView {

    var onValueChanged: ((Double) -> Void)?

    private var _value: Double = 50.0
    private var isDragging = false

    private let trackLayer    = CALayer()
    private let fillLayer     = CAGradientLayer()
    private let glowLayer     = CALayer()
    private let thumbLayer    = CALayer()

    override var isFlipped: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true

        let trackH: CGFloat = 6
        let y = (bounds.height - trackH) / 2

        // Track background
        trackLayer.backgroundColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        trackLayer.cornerRadius    = trackH / 2
        trackLayer.frame           = CGRect(x: 0, y: y, width: bounds.width, height: trackH)
        layer?.addSublayer(trackLayer)

        // Amber gradient fill
        fillLayer.colors     = [
            NSColor(red: 0.90, green: 0.50, blue: 0.05, alpha: 1).cgColor,
            DS.amber.cgColor
        ]
        fillLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.endPoint   = CGPoint(x: 1, y: 0.5)
        fillLayer.cornerRadius = trackH / 2
        layer?.addSublayer(fillLayer)

        // Glow under thumb
        glowLayer.backgroundColor = DS.amber.cgColor
        glowLayer.cornerRadius    = 10
        glowLayer.shadowColor     = DS.amber.cgColor
        glowLayer.shadowRadius    = 8
        glowLayer.shadowOpacity   = 0.7
        glowLayer.shadowOffset    = .zero
        layer?.addSublayer(glowLayer)

        // White thumb
        thumbLayer.backgroundColor = NSColor.white.cgColor
        thumbLayer.cornerRadius    = 10
        thumbLayer.shadowColor     = NSColor.black.cgColor
        thumbLayer.shadowRadius    = 4
        thumbLayer.shadowOpacity   = 0.3
        thumbLayer.shadowOffset    = CGSize(width: 0, height: -1)
        layer?.addSublayer(thumbLayer)

        updateLayers()
    }

    override func layout() {
        super.layout()
        setup()
    }

    private func updateLayers() {
        let trackH: CGFloat = 6
        let thumbD: CGFloat = 18
        let y = (bounds.height - trackH) / 2
        let thumbY = (bounds.height - thumbD) / 2

        let fraction = CGFloat((_value - 0) / 100.0)
        let fillWidth = max(trackH, fraction * bounds.width)
        let thumbX    = fraction * (bounds.width - thumbD)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        trackLayer.frame = CGRect(x: 0, y: y, width: bounds.width, height: trackH)
        fillLayer.frame  = CGRect(x: 0, y: y, width: fillWidth, height: trackH)
        glowLayer.frame  = CGRect(x: thumbX + thumbD/2 - 8, y: thumbY + thumbD/2 - 8, width: 16, height: 16)
        thumbLayer.frame = CGRect(x: thumbX, y: thumbY, width: thumbD, height: thumbD)

        CATransaction.commit()
    }

    func setValue(_ v: Double) {
        _value = max(0, min(100, v))
        updateLayers()
    }

    // Mouse interaction
    override func mouseDown(with event: NSEvent) { isDragging = true; handle(event) }
    override func mouseDragged(with event: NSEvent) { handle(event) }
    override func mouseUp(with event: NSEvent) { isDragging = false; handle(event) }

    private func handle(_ event: NSEvent) {
        let loc    = convert(event.locationInWindow, from: nil)
        let newVal = Double(max(0, min(bounds.width, loc.x))) / Double(bounds.width) * 100.0
        _value     = newVal
        updateLayers()
        onValueChanged?(newVal)
    }
}

// MARK: - StatusBadge

class StatusBadge: NSView {

    private let dot   = NSView()
    private let icon  = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        // Dot
        dot.wantsLayer  = true
        dot.layer?.cornerRadius = 3
        dot.frame = NSRect(x: 0, y: 8, width: 6, height: 6)
        addSubview(dot)

        // SF Symbol icon
        icon.frame = NSRect(x: 14, y: 4, width: 14, height: 14)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        // Label
        label.font      = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = DS.textMuted
        label.frame     = NSRect(x: 32, y: 5, width: 220, height: 14)
        addSubview(label)
    }

    func configure(icon iconName: String, text: String, dotColor: NSColor) {
        dot.layer?.backgroundColor = dotColor.cgColor
        label.stringValue = text
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            icon.image = img.withSymbolConfiguration(cfg)
            icon.contentTintColor = DS.textMuted
        }
    }

    func setDotColor(_ color: NSColor) { dot.layer?.backgroundColor = color.cgColor }
    func setText(_ text: String)       { label.stringValue = text }
}

// MARK: - HoverMenuItem

class HoverMenuItem: NSView {

    var onTap: (() -> Void)?

    private let titleLabel  = NSTextField(labelWithString: "")
    private let keyLabel    = NSTextField(labelWithString: "")
    private var isHovered   = false

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 6

        titleLabel.font      = .systemFont(ofSize: 12)
        titleLabel.textColor = DS.text
        titleLabel.frame     = NSRect(x: 14, y: 3, width: 200, height: 14)
        addSubview(titleLabel)

        keyLabel.font      = .systemFont(ofSize: 10, weight: .regular)
        keyLabel.textColor = DS.textMuted
        keyLabel.alignment = .right
        keyLabel.frame     = NSRect(x: DS.popoverWidth - 60, y: 3, width: 46, height: 14)
        addSubview(keyLabel)

        // Hover tracking
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    func configure(title: String, keyEquiv: String) {
        titleLabel.stringValue = title
        keyLabel.stringValue   = keyEquiv
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = DS.surface2.cgColor
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    override func mouseUp(with event: NSEvent) {
        onTap?()
        // Close menu
        if let menu = enclosingMenuItem?.menu { menu.cancelTracking() }
    }
}

// MARK: - ModernSettingsView

class ModernSettingsView: NSView {

    private let brightnessController: BrightnessController

    private let minSlider     = AmberGradientSlider()
    private let maxSlider     = AmberGradientSlider()
    private let minValueLabel = NSTextField(labelWithString: "20%")
    private let maxValueLabel = NSTextField(labelWithString: "80%")

    init(frame: NSRect, brightnessController: BrightnessController) {
        self.brightnessController = brightnessController
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:brightnessController:)") }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = DS.surface.cgColor

        let W = bounds.width
        let topY: CGFloat = bounds.height - 68

        // ── Section title ─────────────────────────────────────
        let sectionTitle = NSTextField(labelWithString: "MacBook Brightness Limits")
        sectionTitle.font      = .systemFont(ofSize: 14, weight: .semibold)
        sectionTitle.textColor = DS.text
        sectionTitle.frame     = NSRect(x: 24, y: topY + 14, width: W - 48, height: 20)
        addSubview(sectionTitle)

        let sectionDesc = NSTextField(wrappingLabelWithString: "Maps the slider (0–100%) to these internal MacBook brightness values.\nExternal monitors always use 0–100%.")
        sectionDesc.font      = .systemFont(ofSize: 11)
        sectionDesc.textColor = DS.textMuted
        sectionDesc.frame     = NSRect(x: 24, y: topY - 22, width: W - 48, height: 34)
        addSubview(sectionDesc)

        // ── Card background for sliders ───────────────────────
        let card = NSView(frame: NSRect(x: 16, y: topY - 98, width: W - 32, height: 76))
        card.wantsLayer           = true
        card.layer?.backgroundColor = DS.surface2.cgColor
        card.layer?.cornerRadius    = 10
        card.layer?.borderWidth     = 1
        card.layer?.borderColor     = DS.border.cgColor
        addSubview(card)

        // -- Min row --
        styleRowLabel("Minimum (0%)", in: card, frame: NSRect(x: 16, y: 44, width: 120, height: 16))
        minSlider.frame = NSRect(x: 140, y: 40, width: card.bounds.width - 190, height: 22)
        minSlider.setValue(Double(brightnessController.macBookCalibration.minBrightness * 100))
        minSlider.onValueChanged = { [weak self] val in
            guard let self else { return }
            self.brightnessController.macBookCalibration.minBrightness = Float(val) / 100.0
            self.minValueLabel.stringValue = "\(Int(val))%"
        }
        card.addSubview(minSlider)
        styleValueLabel(minValueLabel, pct: Int(brightnessController.macBookCalibration.minBrightness * 100), in: card,
                        frame: NSRect(x: card.bounds.width - 44, y: 44, width: 36, height: 16))

        // Divider
        let div = NSBox()
        div.boxType    = .separator
        div.frame      = NSRect(x: 16, y: 36, width: card.bounds.width - 32, height: 1)
        div.borderColor = DS.separator
        card.addSubview(div)

        // -- Max row --
        styleRowLabel("Maximum (100%)", in: card, frame: NSRect(x: 16, y: 14, width: 120, height: 16))
        maxSlider.frame = NSRect(x: 140, y: 10, width: card.bounds.width - 190, height: 22)
        maxSlider.setValue(Double(brightnessController.macBookCalibration.maxBrightness * 100))
        maxSlider.onValueChanged = { [weak self] val in
            guard let self else { return }
            self.brightnessController.macBookCalibration.maxBrightness = Float(val) / 100.0
            self.maxValueLabel.stringValue = "\(Int(val))%"
        }
        card.addSubview(maxSlider)
        styleValueLabel(maxValueLabel, pct: Int(brightnessController.macBookCalibration.maxBrightness * 100), in: card,
                        frame: NSRect(x: card.bounds.width - 44, y: 14, width: 36, height: 16))

        // ── Keyboard shortcuts pill row ───────────────────────
        let kbLabel = NSTextField(labelWithString: "Shortcuts")
        kbLabel.font      = .systemFont(ofSize: 11)
        kbLabel.textColor = DS.textMuted
        kbLabel.frame     = NSRect(x: 24, y: topY - 120, width: 70, height: 16)
        addSubview(kbLabel)

        for (i, txt) in ["⌥ [  ▼", "⌥ ]  ▲"].enumerated() {
            let pill = makePill(txt)
            pill.frame = NSRect(x: 100 + CGFloat(i) * 80, y: topY - 122, width: 70, height: 20)
            addSubview(pill)
        }

        // ── Reset button ──────────────────────────────────────
        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetCalibration))
        resetBtn.bezelStyle = .rounded
        resetBtn.font       = .systemFont(ofSize: 11)
        resetBtn.frame      = NSRect(x: 24, y: 18, width: 140, height: 26)
        addSubview(resetBtn)
    }

    @discardableResult
    private func styleRowLabel(_ text: String, in parent: NSView, frame: NSRect) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font      = .systemFont(ofSize: 11)
        lbl.textColor = DS.text
        lbl.frame     = frame
        parent.addSubview(lbl)
        return lbl
    }

    private func styleValueLabel(_ lbl: NSTextField, pct: Int, in parent: NSView, frame: NSRect) {
        lbl.font           = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        lbl.textColor      = DS.amber
        lbl.alignment      = .right
        lbl.stringValue    = "\(pct)%"
        lbl.frame          = frame
        parent.addSubview(lbl)
    }

    private func makePill(_ text: String) -> NSView {
        let v = NSView()
        v.wantsLayer             = true
        v.layer?.backgroundColor = DS.amberDim.cgColor
        v.layer?.cornerRadius    = 6
        v.layer?.borderWidth     = 1
        v.layer?.borderColor     = DS.amber.withAlphaComponent(0.3).cgColor

        let lbl = NSTextField(labelWithString: text)
        lbl.font      = .systemFont(ofSize: 10, weight: .medium)
        lbl.textColor = DS.amber
        lbl.alignment = .center
        lbl.frame     = NSRect(x: 2, y: 3, width: 66, height: 14)
        v.addSubview(lbl)
        return v
    }

    @objc private func resetCalibration() {
        brightnessController.macBookCalibration = BrightnessCalibration(minBrightness: 0.20, maxBrightness: 0.80)
        minSlider.setValue(20)
        maxSlider.setValue(80)
        minValueLabel.stringValue = "20%"
        maxValueLabel.stringValue = "80%"
    }
}
