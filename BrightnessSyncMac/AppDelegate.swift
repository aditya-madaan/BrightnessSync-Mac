import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Design Tokens
private enum DS {
    // Amber accent: #f4c025
    static let amber      = NSColor(red: 0.957, green: 0.753, blue: 0.145, alpha: 1)
    static let amberDim   = NSColor(red: 0.957, green: 0.753, blue: 0.145, alpha: 0.18)
    static let amberGlow  = NSColor(red: 0.957, green: 0.753, blue: 0.145, alpha: 0.55)
    static let amberDark  = NSColor(red: 0.78, green: 0.45, blue: 0.02, alpha: 1)   // #c77308

    // Surfaces
    static let bg         = NSColor(red: 0.098, green: 0.098, blue: 0.110, alpha: 1) // #191919
    static let card       = NSColor(red: 0.145, green: 0.145, blue: 0.165, alpha: 1) // #252529
    static let divider    = NSColor(white: 1.0, alpha: 0.09)
    static let border     = NSColor(white: 1.0, alpha: 0.10)

    // Text
    static let textPrimary  = NSColor(white: 1.0, alpha: 0.90)
    static let textSecondary = NSColor(white: 1.0, alpha: 0.48)
    static let greenDot      = NSColor(red: 0.22, green: 0.86, blue: 0.50, alpha: 1)

    // Layout
    static let popW: CGFloat    = 280
    static let popH: CGFloat    = 240
    static let sidePad: CGFloat = 16
    static let radius: CGFloat  = 12

    // Typography helpers
    static func body(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, BrightnessChangeDelegate {

    private var statusItem: NSStatusItem!
    private var brightnessController: BrightnessController!
    private var popoverView: ModernPopoverView!
    private var settingsWindow: NSWindow?
    private var shortcutManager: KeyboardShortcutManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        brightnessController = BrightnessController()
        brightnessController.delegate = self

        shortcutManager = KeyboardShortcutManager()
        shortcutManager.brightnessController = brightnessController
        shortcutManager.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                button.image = img
                button.image?.isTemplate = true
            } else {
                button.title = "☀️"
            }
        }

        setupMenu()
        monitorDisplayChanges()
        brightnessController.startMonitoring()
        checkAccessibilityPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        brightnessController.stopMonitoring()
        shortcutManager.stop()
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermissions() {
        if AXIsProcessTrusted() {
            shortcutManager.start()
        } else {
            promptForAccessibility()
        }
    }

    private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            shortcutManager.start()
        } else {
            showAccessibilityAlert()
            startAccessibilityPolling()
        }
    }

    private func showAccessibilityAlert() {
        let a = NSAlert()
        a.messageText     = "Accessibility Access Required"
        a.informativeText = "BrightnessSync needs Accessibility access for keyboard shortcuts (Option+[ / ]).\n\nEnable in System Settings → Privacy & Security → Accessibility."
        a.alertStyle      = .informational
        a.addButton(withTitle: "Open Settings")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private func startAccessibilityPolling() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
            if AXIsProcessTrusted() { t.invalidate(); self?.shortcutManager.start()
                DispatchQueue.main.async { self?.popoverView?.refreshStatus() }
            }
        }
    }

    // MARK: - BrightnessChangeDelegate
    func brightnessDidChange(sliderValue: Float) { popoverView?.refreshBrightness() }

    private func monitorDisplayChanges() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, ui in
            guard let ui else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(ui).takeUnretainedValue()
            if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) {
                DispatchQueue.main.async { me.handleDisplayChange() }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func handleDisplayChange() {
        let c = brightnessController.getBrightness()
        brightnessController.setBrightness(c)
        popoverView?.refreshStatus()
    }

    // MARK: - Menu

    private func setupMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        popoverView = ModernPopoverView(
            frame: NSRect(x: 0, y: 0, width: DS.popW, height: DS.popH),
            brightnessController: brightnessController,
            onSettings: { [weak self] in self?.openSettings() },
            onQuit:     { NSApp.terminate(nil) }
        )
        item.view = popoverView
        menu.addItem(item)
        statusItem.menu    = menu
        menu.delegate      = self
    }

    @objc private func openSettings() {
        if settingsWindow == nil { createSettingsWindow() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createSettingsWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 270),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "Calibration Settings"
        w.titlebarAppearsTransparent = true
        w.center()
        w.isReleasedWhenClosed = false
        w.backgroundColor = DS.bg
        w.contentView = ModernSettingsView(
            frame: NSRect(x: 0, y: 0, width: 380, height: 270),
            controller: brightnessController
        )
        settingsWindow = w
    }
}

// MARK: - NSMenuDelegate
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        popoverView?.refreshBrightness()
        popoverView?.refreshStatus()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - ModernPopoverView
// ═══════════════════════════════════════════════════════════

final class ModernPopoverView: NSView {

    private let bc: BrightnessController
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    // Subviews we need to update
    private let pctLabel   = NSTextField(labelWithString: "–%")
    private let slider     = AmberSlider()
    private let syncBadge  = BadgeRow()
    private let kbBadge    = BadgeRow()
    private let dispBadge  = BadgeRow()

    init(frame: NSRect,
         brightnessController: BrightnessController,
         onSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.bc         = brightnessController
        self.onSettings = onSettings
        self.onQuit     = onQuit
        super.init(frame: frame)
        wantsLayer            = true
        layer?.backgroundColor = DS.bg.cgColor
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    // ─── Layout constants ─────────────────────────────────
    private let H: CGFloat = DS.popH   // 240
    private let W: CGFloat = DS.popW   // 280
    private let P: CGFloat = DS.sidePad // 16

    private func buildLayout() {
        // All Y values measured from bottom (NS coordinate origin)

        // ── 1. BOTTOM ACTION ROW (Quit) ─── y: 0..22
        let quitRow = ActionRow(title: "Quit BrightnessSync", key: "⌘Q")
        quitRow.onTap = { [weak self] in self?.onQuit() }
        quitRow.frame = NSRect(x: 0, y: 0, width: W, height: 26)
        addSubview(quitRow)

        // ── 2. Settings row ─── y: 26..52
        let settingsRow = ActionRow(title: "Calibration Settings…", key: "⌘,")
        settingsRow.onTap = { [weak self] in self?.onSettings() }
        settingsRow.frame = NSRect(x: 0, y: 26, width: W, height: 26)
        addSubview(settingsRow)

        // ── Divider ─── y: 52
        addDivider(y: 52)

        // ── 3. STATUS BADGES ─── y: 60..134
        syncBadge.configure(dotColor: DS.greenDot,  sfSymbol: "arrow.triangle.2.circlepath", text: "Syncing with F1 / F2")
        kbBadge.configure(dotColor: DS.amber,        sfSymbol: "keyboard",                    text: "⌥[ / ] shortcuts active")
        dispBadge.configure(dotColor: DS.textSecondary, sfSymbol: "display",                 text: "1 display connected")

        syncBadge.frame  = NSRect(x: 0, y: 112, width: W, height: 26)
        kbBadge.frame    = NSRect(x: 0, y: 86,  width: W, height: 26)
        dispBadge.frame  = NSRect(x: 0, y: 60,  width: W, height: 26)
        addSubview(syncBadge)
        addSubview(kbBadge)
        addSubview(dispBadge)

        // ── Divider ─── y: 138
        addDivider(y: 138)

        // ── 4. SLIDER SECTION ─── y: 148..192
        // "BRIGHTNESS" label + pctLabel
        let bLabel = makeLabel("BRIGHTNESS", font: DS.body(9, weight: .semibold), color: DS.textSecondary)
        bLabel.frame = NSRect(x: P, y: 178, width: 90, height: 12)
        bLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(bLabel)

        pctLabel.font          = DS.mono(13, weight: .bold)
        pctLabel.textColor     = DS.amber
        pctLabel.alignment     = .right
        pctLabel.frame         = NSRect(x: W - P - 50, y: 176, width: 50, height: 16)
        addSubview(pctLabel)

        // Slider
        slider.frame = NSRect(x: P, y: 150, width: W - P * 2, height: 22)
        slider.onChanged = { [weak self] val in
            guard let self else { return }
            self.bc.setBrightness(Float(val / 100.0))
            self.pctLabel.stringValue = "\(Int(val))%"
        }
        addSubview(slider)

        // ── Divider ─── y: 144
        addDivider(y: 144)

        // ── 5. HEADER ─── y: 200..240
        // Sun icon (SF Symbol, amber tinted)
        let sunView = NSImageView(frame: NSRect(x: P, y: 212, width: 18, height: 18))
        let sunCfg  = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(sunCfg) {
            sunView.image = img
        }
        sunView.contentTintColor = DS.amber
        sunView.imageScaling     = .scaleProportionallyUpOrDown
        addSubview(sunView)

        let titleField = makeLabel("BrightnessSync",
                                   font: DS.body(13, weight: .semibold),
                                   color: DS.textPrimary)
        titleField.frame = NSRect(x: P + 26, y: 212, width: 180, height: 18)
        addSubview(titleField)

        // Bottom hairline below header
        addDivider(y: 206)
    }

    @discardableResult
    private func addDivider(y: CGFloat) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: y, width: W, height: 1))
        v.wantsLayer            = true
        v.layer?.backgroundColor = DS.divider.cgColor
        addSubview(v)
        return v
    }

    private func makeLabel(_ s: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font      = font
        f.textColor = color
        return f
    }

    // ─── Public refresh ───────────────────────────────────
    func refreshBrightness() {
        let b = bc.getBrightness()
        slider.setValue(Double(b * 100))
        pctLabel.stringValue = "\(Int(b * 100))%"
    }

    func refreshStatus() {
        let active = AXIsProcessTrusted()
        kbBadge.setDotColor(active ? DS.amber : DS.textSecondary)
        kbBadge.setText(active ? "⌥[ / ] shortcuts active" : "⌥[ / ] needs permissions")

        let count = bc.getDisplayCount()
        dispBadge.setText("\(count) display\(count == 1 ? "" : "s") connected")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBrightness()
        refreshStatus()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - AmberSlider   (custom CALayer-based slider)
// ═══════════════════════════════════════════════════════════

final class AmberSlider: NSView {

    var onChanged: ((Double) -> Void)?
    private var value: Double = 50  // 0..100

    private let trackBg    = CALayer()
    private let trackFill  = CAGradientLayer()
    private let glowLayer  = CALayer()
    private let thumb      = CALayer()

    override var isFlipped: Bool { false }

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let tH: CGFloat = 5
        // Track background
        trackBg.cornerRadius  = tH / 2
        trackBg.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
        layer?.addSublayer(trackBg)

        // Amber gradient fill
        trackFill.cornerRadius = tH / 2
        trackFill.colors       = [DS.amberDark.cgColor, DS.amber.cgColor]
        trackFill.startPoint   = CGPoint(x: 0, y: 0.5)
        trackFill.endPoint     = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(trackFill)

        // Glow behind thumb
        glowLayer.cornerRadius  = 9
        glowLayer.shadowColor   = DS.amber.cgColor
        glowLayer.shadowRadius  = 7
        glowLayer.shadowOpacity = 0.75
        glowLayer.shadowOffset  = .zero
        glowLayer.backgroundColor = DS.amberGlow.cgColor
        layer?.addSublayer(glowLayer)

        // White thumb
        thumb.cornerRadius     = 10
        thumb.backgroundColor  = NSColor.white.cgColor
        thumb.shadowColor      = NSColor.black.cgColor
        thumb.shadowRadius     = 3
        thumb.shadowOpacity    = 0.30
        thumb.shadowOffset     = CGSize(width: 0, height: -1)
        layer?.addSublayer(thumb)
    }

    override func layout() {
        super.layout()
        refreshLayers()
    }

    func setValue(_ v: Double) {
        value = v.clamped(to: 0...100)
        refreshLayers()
    }

    private func refreshLayers() {
        guard bounds.width > 0 else { return }

        let tH: CGFloat  = 5
        let tY: CGFloat  = (bounds.height - tH) / 2
        let tD: CGFloat  = 20        // thumb diameter
        let tY2: CGFloat = (bounds.height - tD) / 2

        let fraction  = CGFloat(value / 100.0)
        let usable    = bounds.width - tD
        let thumbX    = fraction * usable
        let fillW     = max(tH, thumbX + tD / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackBg.frame   = CGRect(x: 0,      y: tY,  width: bounds.width, height: tH)
        trackFill.frame = CGRect(x: 0,      y: tY,  width: fillW,        height: tH)
        glowLayer.frame = CGRect(x: thumbX + tD/2 - 9, y: tY2 + tD/2 - 9, width: 18, height: 18)
        thumb.frame     = CGRect(x: thumbX, y: tY2, width: tD,           height: tD)
        CATransaction.commit()
    }

    override func mouseDown(with e: NSEvent)    { drag(e) }
    override func mouseDragged(with e: NSEvent) { drag(e) }
    override func mouseUp(with e: NSEvent)      { drag(e) }

    private func drag(_ e: NSEvent) {
        let x   = convert(e.locationInWindow, from: nil).x
        let tD: CGFloat = 20
        let raw = (x - tD / 2) / (bounds.width - tD) * 100
        value   = raw.clamped(to: 0...100)
        refreshLayers()
        onChanged?(value)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - BadgeRow
// ═══════════════════════════════════════════════════════════

final class BadgeRow: NSView {

    private let dot   = NSView()
    private let icon  = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        // Dot  — 6×6, centred vertically
        dot.wantsLayer     = true
        dot.frame          = NSRect(x: DS.sidePad, y: 10, width: 6, height: 6)
        dot.layer?.cornerRadius = 3
        addSubview(dot)

        // SF Symbol icon — 13×13
        icon.frame         = NSRect(x: DS.sidePad + 14, y: 7, width: 13, height: 13)
        icon.imageScaling  = .scaleProportionallyUpOrDown
        addSubview(icon)

        // Label
        label.font         = DS.body(11)
        label.textColor    = DS.textSecondary
        label.frame        = NSRect(x: DS.sidePad + 32, y: 6, width: DS.popW - DS.sidePad - 40, height: 14)
        addSubview(label)
    }

    func configure(dotColor: NSColor, sfSymbol: String, text: String) {
        dot.layer?.backgroundColor = dotColor.cgColor
        label.stringValue          = text
        if let img = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular)) {
            icon.image            = img
            icon.contentTintColor = DS.textSecondary
        }
    }

    func setDotColor(_ c: NSColor) { dot.layer?.backgroundColor = c.cgColor }
    func setText(_ t: String)       { label.stringValue = t }
}

// ═══════════════════════════════════════════════════════════
// MARK: - ActionRow  (Settings / Quit)
// ═══════════════════════════════════════════════════════════

final class ActionRow: NSView {

    var onTap: (() -> Void)?
    private let titleLbl = NSTextField(labelWithString: "")
    private let keyLbl   = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?

    init(title: String, key: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 0
        titleLbl.font      = DS.body(12)
        titleLbl.textColor = DS.textPrimary
        titleLbl.frame     = NSRect(x: DS.sidePad, y: 6, width: 200, height: 15)
        addSubview(titleLbl)

        keyLbl.font        = DS.body(10)
        keyLbl.textColor   = DS.textSecondary
        keyLbl.alignment   = .right
        keyLbl.frame       = NSRect(x: DS.popW - DS.sidePad - 44, y: 7, width: 44, height: 13)
        addSubview(keyLbl)

        titleLbl.stringValue = title
        keyLbl.stringValue   = key
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    override func mouseEntered(with e: NSEvent) {
        layer?.backgroundColor = DS.card.cgColor
    }
    override func mouseExited(with e: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    override func mouseUp(with e: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        onTap?()
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - ModernSettingsView
// ═══════════════════════════════════════════════════════════

final class ModernSettingsView: NSView {

    private let bc: BrightnessController
    private let minSlider = AmberSlider()
    private let maxSlider = AmberSlider()
    private let minLbl    = NSTextField(labelWithString: "20%")
    private let maxLbl    = NSTextField(labelWithString: "80%")

    init(frame: NSRect, controller: BrightnessController) {
        self.bc = controller
        super.init(frame: frame)
        wantsLayer            = true
        layer?.backgroundColor = DS.bg.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let W = bounds.width   // 380
        let P = DS.sidePad + 8 // 24

        // ── Section heading ───────────────────────────────
        let heading = label("MacBook Brightness Limits", font: DS.body(14, weight: .semibold), color: DS.textPrimary)
        heading.frame = NSRect(x: P, y: 220, width: W - P*2, height: 20)
        addSubview(heading)

        let sub = wrappingLabel("Maps the slider (0–100%) to these MacBook brightness values.\nExternal monitors always use the full 0–100% range.",
                                font: DS.body(11), color: DS.textSecondary)
        sub.frame = NSRect(x: P, y: 178, width: W - P*2, height: 40)
        addSubview(sub)

        // ── Slider card ───────────────────────────────────
        let card = NSView(frame: NSRect(x: 16, y: 90, width: W - 32, height: 84))
        card.wantsLayer             = true
        card.layer?.backgroundColor = DS.card.cgColor
        card.layer?.cornerRadius    = 10
        card.layer?.borderWidth     = 1
        card.layer?.borderColor     = DS.border.cgColor
        addSubview(card)

        let cW = card.bounds.width

        // Min row (top of card)
        let minRowLabel = label("Minimum · 0%", font: DS.body(11), color: DS.textPrimary)
        minRowLabel.frame = NSRect(x: 14, y: 52, width: 100, height: 16)
        card.addSubview(minRowLabel)

        minSlider.frame = NSRect(x: 128, y: 48, width: cW - 128 - 54, height: 22)
        minSlider.setValue(Double(bc.macBookCalibration.minBrightness * 100))
        minSlider.onChanged = { [weak self] v in
            guard let self else { return }
            self.bc.macBookCalibration.minBrightness = Float(v / 100)
            self.minLbl.stringValue = "\(Int(v))%"
        }
        card.addSubview(minSlider)

        minLbl.font           = DS.mono(11, weight: .semibold)
        minLbl.textColor      = DS.amber
        minLbl.alignment      = .right
        minLbl.stringValue    = "\(Int(bc.macBookCalibration.minBrightness * 100))%"
        minLbl.frame          = NSRect(x: cW - 46, y: 52, width: 38, height: 16)
        card.addSubview(minLbl)

        // Divider within card
        let div = NSView(frame: NSRect(x: 14, y: 42, width: cW - 28, height: 1))
        div.wantsLayer            = true
        div.layer?.backgroundColor = DS.divider.cgColor
        card.addSubview(div)

        // Max row (bottom of card)
        let maxRowLabel = label("Maximum · 100%", font: DS.body(11), color: DS.textPrimary)
        maxRowLabel.frame = NSRect(x: 14, y: 18, width: 100, height: 16)
        card.addSubview(maxRowLabel)

        maxSlider.frame = NSRect(x: 128, y: 14, width: cW - 128 - 54, height: 22)
        maxSlider.setValue(Double(bc.macBookCalibration.maxBrightness * 100))
        maxSlider.onChanged = { [weak self] v in
            guard let self else { return }
            self.bc.macBookCalibration.maxBrightness = Float(v / 100)
            self.maxLbl.stringValue = "\(Int(v))%"
        }
        card.addSubview(maxSlider)

        maxLbl.font        = DS.mono(11, weight: .semibold)
        maxLbl.textColor   = DS.amber
        maxLbl.alignment   = .right
        maxLbl.stringValue = "\(Int(bc.macBookCalibration.maxBrightness * 100))%"
        maxLbl.frame       = NSRect(x: cW - 46, y: 18, width: 38, height: 16)
        card.addSubview(maxLbl)

        // ── Shortcut pills ────────────────────────────────
        let kbTitle = label("Keyboard shortcuts", font: DS.body(11), color: DS.textSecondary)
        kbTitle.frame = NSRect(x: P, y: 62, width: 140, height: 16)
        addSubview(kbTitle)

        for (i, txt) in ["⌥ [   dim", "⌥ ]   bright"].enumerated() {
            addSubview(makePill(txt, x: P + CGFloat(i) * 100, y: 40))
        }

        // ── Reset button ──────────────────────────────────
        let btn = NSButton(title: "Reset to Defaults", target: self, action: #selector(reset))
        btn.bezelStyle = .rounded
        btn.font       = DS.body(11)
        btn.frame      = NSRect(x: P, y: 14, width: 140, height: 26)
        addSubview(btn)
    }

    private func makePill(_ text: String, x: CGFloat, y: CGFloat) -> NSView {
        let v = NSView(frame: NSRect(x: x, y: y, width: 92, height: 22))
        v.wantsLayer             = true
        v.layer?.backgroundColor = DS.amberDim.cgColor
        v.layer?.cornerRadius    = 6
        v.layer?.borderWidth     = 1
        v.layer?.borderColor     = DS.amber.withAlphaComponent(0.3).cgColor
        let lbl = NSTextField(labelWithString: text)
        lbl.font      = DS.body(10, weight: .medium)
        lbl.textColor = DS.amber
        lbl.alignment = .center
        lbl.frame     = NSRect(x: 2, y: 4, width: 88, height: 14)
        v.addSubview(lbl)
        return v
    }

    private func label(_ s: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: s); f.font = font; f.textColor = color; return f
    }
    private func wrappingLabel(_ s: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: s); f.font = font; f.textColor = color; return f
    }

    @objc private func reset() {
        bc.macBookCalibration = BrightnessCalibration(minBrightness: 0.20, maxBrightness: 0.80)
        minSlider.setValue(20); maxSlider.setValue(80)
        minLbl.stringValue = "20%"; maxLbl.stringValue = "80%"
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - Clamped helper
// ═══════════════════════════════════════════════════════════
extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
