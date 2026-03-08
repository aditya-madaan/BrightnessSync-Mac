import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Design Tokens (from Stitch HTML)
// background-dark: #221e10  |  primary: #f4c025
// slate-800/50 badges  |  emerald-500 sync dot  |  red-400/500 quit
private enum DS {
    // Primary amber
    static let primary       = NSColor(srgbRed: 0.957, green: 0.753, blue: 0.145, alpha: 1) // #f4c025
    static let primarySubtle = NSColor(srgbRed: 0.957, green: 0.753, blue: 0.145, alpha: 0.20)

    // Surfaces  — warm dark, matching Stitch `rgba(34,30,16,0.75)`
    static let bgWarm        = NSColor(srgbRed: 0.133, green: 0.118, blue: 0.063, alpha: 1)  // #221e10
    static let bgCard        = NSColor(srgbRed: 0.117, green: 0.161, blue: 0.231, alpha: 0.5) // slate-800/50
    static let bgCardHoverAmber = NSColor(srgbRed: 0.957, green: 0.753, blue: 0.145, alpha: 0.15)
    static let bgCardHoverRed   = NSColor(srgbRed: 0.94,  green: 0.27,  blue: 0.27,  alpha: 0.18)

    // Text
    static let textPrimary  = NSColor(white: 0.92, alpha: 1)         // slate-100
    static let textMuted    = NSColor(white: 0.62, alpha: 1)         // slate-400
    static let textRed      = NSColor(srgbRed: 0.93, green: 0.40, blue: 0.40, alpha: 1)  // red-400

    // Status colours
    static let emerald      = NSColor(srgbRed: 0.063, green: 0.725, blue: 0.506, alpha: 1) // emerald-500
    static let divider      = NSColor(white: 1.0, alpha: 0.10)       // slate-700/50

    // Layout constants
    static let popW: CGFloat    = 280   // w-[280px]
    static let px: CGFloat      = 16    // px-4
    static let badgePx: CGFloat = 10    // px-2.5
    static let badgePy: CGFloat = 7     // py-1.5
    static let badgeGap: CGFloat = 8    // gap-2
    static let sectionGap: CGFloat = 16 // gap-4

    static func body(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
    static var mono: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .semibold) }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, BrightnessChangeDelegate {

    private var statusItem: NSStatusItem!
    private var brightnessController: BrightnessController!
    private var popoverView: BrightnessSyncPopover!
    private var settingsWindow: NSWindow?
    private var shortcutManager: KeyboardShortcutManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        brightnessController = BrightnessController()
        brightnessController.delegate = self

        shortcutManager = KeyboardShortcutManager()
        shortcutManager.brightnessController = brightnessController
        shortcutManager.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                btn.image = img; btn.image?.isTemplate = true
            } else { btn.title = "☀️" }
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
        if AXIsProcessTrusted() { shortcutManager.start() }
        else { promptForAccessibility() }
    }
    private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) { shortcutManager.start() }
        else { showAccessibilityAlert(); startAccessibilityPolling() }
    }
    private func showAccessibilityAlert() {
        let a = NSAlert()
        a.messageText     = "Accessibility Access Required"
        a.informativeText = "BrightnessSync needs Accessibility access for keyboard shortcuts (Option+[ / ]).\n\nEnable in System Settings → Privacy & Security → Accessibility."
        a.alertStyle      = .informational
        a.addButton(withTitle: "Open Settings")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    private func startAccessibilityPolling() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
            if AXIsProcessTrusted() {
                t.invalidate()
                self?.shortcutManager.start()
                DispatchQueue.main.async { self?.popoverView?.refreshStatus() }
            }
        }
    }

    // MARK: - BrightnessChangeDelegate
    func brightnessDidChange(sliderValue: Float) { popoverView?.refreshBrightness() }

    // MARK: - Display monitoring
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
        brightnessController.setBrightness(brightnessController.getBrightness())
        popoverView?.refreshStatus()
    }

    // MARK: - Menu
    private func setupMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        popoverView = BrightnessSyncPopover(
            brightnessController: brightnessController,
            onSettings: { [weak self] in self?.openSettings() },
            onQuit:     { NSApp.terminate(nil) }
        )
        item.view = popoverView
        menu.addItem(item)
        statusItem.menu = menu
        menu.delegate   = self
    }

    @objc private func openSettings() {
        if settingsWindow == nil { createSettingsWindow() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings Window
    private func createSettingsWindow() {
        // w-[350px], glassmorphic bg-black/40 backdrop-blur-xl, border border-white/10
        // NSWindow title bar is ~28px; content height ~220px → total ~248px
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "Calibration Settings"
        win.center()
        win.isReleasedWhenClosed = false

        // Glassmorphic base: NSVisualEffectView (backdrop-blur)
        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 350, height: 220))
        vfx.material        = .underWindowBackground
        vfx.blendingMode    = .behindWindow
        vfx.state           = .active
        vfx.appearance      = NSAppearance(named: .darkAqua)

        // Dark overlay (bg-black/40)
        let overlay = NSView(frame: vfx.bounds)
        overlay.wantsLayer             = true
        overlay.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        vfx.addSubview(overlay)

        let content = CalibrationSettingsView(
            frame: NSRect(x: 0, y: 0, width: 350, height: 220),
            controller: brightnessController
        )
        vfx.addSubview(content)
        win.contentView = vfx
        settingsWindow = win
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        popoverView?.refreshBrightness()
        popoverView?.refreshStatus()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - BrightnessSyncPopover
// Matches Stitch HTML layout exactly
// ═══════════════════════════════════════════════════════════

final class BrightnessSyncPopover: NSView {

    // Public refresh
    private let bc: BrightnessController
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    private let pctLabel   = NSTextField(labelWithString: "50%")
    private let slider     = StitchSlider()
    private let kbBadge    = BadgeCard()
    private let dispBadge  = BadgeCard()

    // Total height: header(46) + divider(1) + content(badge3*34+2*8+brightness50+gap16+padding24) + divider(1) + menu(72)
    private static let totalH: CGFloat = 330

    init(brightnessController: BrightnessController,
         onSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.bc         = brightnessController
        self.onSettings = onSettings
        self.onQuit     = onQuit
        super.init(frame: NSRect(x: 0, y: 0, width: DS.popW, height: Self.totalH))
        wantsLayer = true
        layer?.backgroundColor = DS.bgWarm.cgColor
        layer?.borderWidth     = 1
        layer?.borderColor     = NSColor(white: 1, alpha: 0.10).cgColor
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        let W  = DS.popW       // 280
        let px = DS.px         // 16
        var y: CGFloat = 0     // building from BOTTOM up

        // ─── Menu Section (bottom) ────────────────────────
        // py-1 (4pt) + two buttons(30pt each) + gap(2pt) + py-1(4pt) = 70pt
        let menuTopPad:    CGFloat = 4
        let menuBotPad:    CGFloat = 4
        let menuItemH:     CGFloat = 30
        let menuPx:        CGFloat = 4   // px-1

        // Quit button
        y += menuBotPad
        let quitBtn = MenuItemRow(title: "Quit BrightnessSync",
                                  rightText: "⌘Q",
                                  hoverColor: DS.bgCardHoverRed,
                                  hoverTextColor: DS.textRed)
        quitBtn.frame = NSRect(x: menuPx, y: y, width: W - menuPx*2, height: menuItemH)
        quitBtn.onTap = { [weak self] in self?.onQuit() }
        addSubview(quitBtn)
        y += menuItemH + 2 // mt-0.5

        // Settings button
        let settingsBtn = MenuItemRow(title: "Calibration Settings...",
                                      sfRightIcon: "gearshape",
                                      hoverColor: DS.primarySubtle,
                                      hoverTextColor: DS.primary)
        settingsBtn.frame = NSRect(x: menuPx, y: y, width: W - menuPx*2, height: menuItemH)
        settingsBtn.onTap = { [weak self] in self?.onSettings() }
        addSubview(settingsBtn)
        y += menuItemH + menuTopPad

        // ─── Full-width divider ───────────────────────────
        addDivider(y: y, width: W)
        y += 1

        // ─── Content Section ──────────────────────────────
        // py-3 = 12pt top (added at end) + py-3 = 12pt bottom (add now)
        y += 12 // bottom py-3

        // Display badge
        dispBadge.setIcon(sfSymbol: "display", text: "1 display connected")
        dispBadge.frame = NSRect(x: px, y: y, width: W - px*2, height: 32)
        addSubview(dispBadge)
        y += 32 + DS.badgeGap  // +8 gap

        // Keyboard badge
        kbBadge.setIcon(sfSymbol: "keyboard", text: "⌥[ / ] shortcuts active")
        kbBadge.frame = NSRect(x: px, y: y, width: W - px*2, height: 32)
        addSubview(kbBadge)
        y += 32 + DS.badgeGap  // +8 gap

        // Sync badge (green dot only, no icon)
        let syncBadge = SyncBadgeCard(text: "Syncing with F1 / F2")
        syncBadge.frame = NSRect(x: px, y: y, width: W - px*2, height: 32)
        addSubview(syncBadge)
        y += 32

        // gap-4 between badges and brightness
        y += DS.sectionGap  // 16

        // Slider row
        slider.frame = NSRect(x: px, y: y, width: W - px*2, height: 24)
        slider.onChanged = { [weak self] val in
            guard let self else { return }
            self.bc.setBrightness(Float(val / 100.0))
            self.pctLabel.stringValue = "\(Int(val))%"
        }
        addSubview(slider)
        y += 24 + 8  // gap-2

        // Brightness label row: "Brightness" (left) + "72%" (right)
        let bLabel = makeText("Brightness", font: DS.body(11, weight: .medium), color: DS.textMuted)
        bLabel.frame = NSRect(x: px, y: y, width: 100, height: 15)
        addSubview(bLabel)

        pctLabel.font      = DS.mono
        pctLabel.textColor = DS.primary
        pctLabel.alignment = .right
        pctLabel.frame     = NSRect(x: W - px - 48, y: y, width: 48, height: 15)
        addSubview(pctLabel)
        y += 15

        // Top py-3 padding
        y += 12

        // ─── Full-width divider ───────────────────────────
        addDivider(y: y, width: W)
        y += 1

        // ─── Header Section ───────────────────────────────
        // pt-4 (16) + icon+title (20) + pb-2 (8) = 44
        y += 8  // pb-2

        // Sun icon — amber tinted SF Symbol
        let sunView = NSImageView()
        let sunCfg  = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(sunCfg) {
            sunView.image = img
        }
        sunView.contentTintColor = DS.primary
        sunView.imageScaling     = .scaleProportionallyUpOrDown
        sunView.frame            = NSRect(x: px, y: y, width: 20, height: 20)
        addSubview(sunView)

        let titleField = makeText("BrightnessSync", font: DS.body(13, weight: .semibold), color: DS.textPrimary)
        titleField.frame = NSRect(x: px + 28, y: y, width: 180, height: 20)
        addSubview(titleField)
        y += 20 + 16  // pt-4

        // Resize self to actual content height
        let finalH = y
        frame = NSRect(x: 0, y: 0, width: W, height: finalH)
    }

    @discardableResult
    private func addDivider(y: CGFloat, width: CGFloat) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: y, width: width, height: 1))
        v.wantsLayer             = true
        v.layer?.backgroundColor = DS.divider.cgColor
        addSubview(v)
        return v
    }

    private func makeText(_ s: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: s); f.font = font; f.textColor = color; return f
    }

    // ─── Refresh ─────────────────────────────────────────
    func refreshBrightness() {
        let b = bc.getBrightness()
        slider.setValue(Double(b * 100))
        pctLabel.stringValue = "\(Int(b * 100))%"
    }

    func refreshStatus() {
        let active = AXIsProcessTrusted()
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
// MARK: - StitchSlider  (matches Stitch CSS slider)
// ═══════════════════════════════════════════════════════════

final class StitchSlider: NSView {

    var onChanged: ((Double) -> Void)?
    private(set) var value: Double = 50

    // Layers
    private let trackBg   = CALayer()
    private let trackFill = CAGradientLayer()
    private let thumb     = CALayer()

    override var isFlipped: Bool { false }

    override init(frame: NSRect) { super.init(frame: frame); setupLayers() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupLayers() }

    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // h-1.5 track = 6px, rounded-full, dark bg
        trackBg.cornerRadius    = 3
        trackBg.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        layer?.addSublayer(trackBg)

        // amber gradient fill: from-amber-500 to-primary
        let amber500 = NSColor(srgbRed: 0.961, green: 0.620, blue: 0.043, alpha: 1)
        trackFill.colors      = [amber500.cgColor, DS.primary.cgColor]
        trackFill.startPoint  = CGPoint(x: 0, y: 0.5)
        trackFill.endPoint    = CGPoint(x: 1, y: 0.5)
        trackFill.cornerRadius = 3
        layer?.addSublayer(trackFill)

        // w-4 h-4 white thumb, shadow, rounded-full
        thumb.cornerRadius    = 8  // 16px thumb → r=8
        thumb.backgroundColor = NSColor.white.cgColor
        thumb.shadowColor     = NSColor.black.cgColor
        thumb.shadowRadius    = 3
        thumb.shadowOpacity   = 0.25
        thumb.shadowOffset    = CGSize(width: 0, height: -1)
        // border: border-slate-600
        thumb.borderWidth     = 0.5
        thumb.borderColor     = NSColor(white: 0.6, alpha: 0.5).cgColor
        layer?.addSublayer(thumb)
    }

    override func layout() {
        super.layout()
        positionLayers()
    }

    func setValue(_ v: Double) {
        value = max(0, min(100, v))
        positionLayers()
    }

    private func positionLayers() {
        guard bounds.width > 0 else { return }

        let tH: CGFloat  = 6   // h-1.5 = 6px
        let tD: CGFloat  = 16  // w-4 h-4 = 16px
        let tY: CGFloat  = (bounds.height - tH) / 2
        let tY2: CGFloat = (bounds.height - tD) / 2
        let usable       = bounds.width - tD
        let thumbX       = CGFloat(value / 100.0) * usable
        let fillW        = max(tH, thumbX + tD / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackBg.frame   = CGRect(x: 0,      y: tY,  width: bounds.width, height: tH)
        trackFill.frame = CGRect(x: 0,      y: tY,  width: fillW,        height: tH)
        thumb.frame     = CGRect(x: thumbX, y: tY2, width: tD,           height: tD)
        CATransaction.commit()
    }

    // Mouse drag
    override func mouseDown(with e: NSEvent)    { handleDrag(e) }
    override func mouseDragged(with e: NSEvent) { handleDrag(e) }
    override func mouseUp(with e: NSEvent)      { handleDrag(e) }

    private func handleDrag(_ e: NSEvent) {
        let tD: CGFloat = 16
        let x   = convert(e.locationInWindow, from: nil).x
        let raw = (x - tD / 2) / (bounds.width - tD) * 100
        value   = max(0, min(100, raw))
        positionLayers()
        onChanged?(value)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - BadgeCard  (icon + label, rounded dark bg)
// Matches: flex items-center gap-2 px-2.5 py-1.5 rounded-md bg-slate-800/50
// ═══════════════════════════════════════════════════════════

final class BadgeCard: NSView {

    private let iconView = NSImageView()
    private let label    = NSTextField(labelWithString: "")

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        wantsLayer             = true
        // bg-slate-800/50  rounded-md
        layer?.backgroundColor = NSColor(srgbRed: 0.117, green: 0.161, blue: 0.231, alpha: 0.50).cgColor
        layer?.cornerRadius    = 6  // rounded-md

        // gap-2 = 8px, px-2.5 = 10px, py-1.5 = 6px
        // icon 16×16 at x=10, centered vertically
        iconView.imageScaling  = .scaleProportionallyUpOrDown
        iconView.frame         = NSRect(x: 10, y: 8, width: 14, height: 14)
        addSubview(iconView)

        label.font      = DS.body(11, weight: .medium)
        label.textColor = DS.textPrimary
        label.frame     = NSRect(x: 32, y: 9, width: 200, height: 14)
        addSubview(label)
    }

    func setIcon(sfSymbol: String, text: String) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if let img = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: nil)?
                        .withSymbolConfiguration(cfg) {
            iconView.image            = img
            iconView.contentTintColor = DS.textMuted
        }
        label.stringValue = text
    }

    func setText(_ t: String) { label.stringValue = t }
}

// ═══════════════════════════════════════════════════════════
// MARK: - SyncBadgeCard  (green dot + label)
// ═══════════════════════════════════════════════════════════

final class SyncBadgeCard: NSView {

    private let dot   = NSView()
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        build(text: text)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(text: String) {
        wantsLayer             = true
        layer?.backgroundColor = NSColor(srgbRed: 0.117, green: 0.161, blue: 0.231, alpha: 0.50).cgColor
        layer?.cornerRadius    = 6

        // w-2 h-2 rounded-full bg-emerald-500
        dot.wantsLayer             = true
        dot.layer?.backgroundColor = DS.emerald.cgColor
        dot.layer?.cornerRadius    = 4
        dot.frame                  = NSRect(x: 10, y: 12, width: 8, height: 8)
        addSubview(dot)

        label.font        = DS.body(11, weight: .medium)
        label.textColor   = DS.textPrimary
        label.stringValue = text
        label.frame       = NSRect(x: 26, y: 9, width: 210, height: 14)
        addSubview(label)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - MenuItemRow
// Matches: flex items-center justify-between px-3 py-1.5 text-sm rounded hover:...
// ═══════════════════════════════════════════════════════════

final class MenuItemRow: NSView {

    var onTap: (() -> Void)?
    private let titleLabel    = NSTextField(labelWithString: "")
    private let rightLabel    = NSTextField(labelWithString: "")
    private let rightIconView = NSImageView()
    private let hoverColor: NSColor
    private let hoverTextColor: NSColor
    private var tracking: NSTrackingArea?

    init(title: String,
         rightText: String? = nil,
         sfRightIcon: String? = nil,
         hoverColor: NSColor,
         hoverTextColor: NSColor) {
        self.hoverColor     = hoverColor
        self.hoverTextColor = hoverTextColor
        super.init(frame: .zero)
        wantsLayer        = true
        layer?.cornerRadius = 6  // rounded

        // Title: px-3 = 12px, centred vertically at py-1.5
        titleLabel.font        = DS.body(12)
        titleLabel.textColor   = DS.textPrimary
        titleLabel.stringValue = title
        titleLabel.frame       = NSRect(x: 12, y: 8, width: 200, height: 14)
        addSubview(titleLabel)

        if let txt = rightText {
            rightLabel.font        = DS.body(11)
            rightLabel.textColor   = DS.textMuted
            rightLabel.stringValue = txt
            rightLabel.alignment   = .right
            rightLabel.frame       = NSRect(x: DS.popW - 12 - 40, y: 8, width: 40, height: 14)
            addSubview(rightLabel)
        }

        if let sym = sfRightIcon,
           let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?
                       .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) {
            rightIconView.image            = img
            rightIconView.contentTintColor = DS.textMuted
            rightIconView.imageScaling     = .scaleProportionallyUpOrDown
            rightIconView.frame            = NSRect(x: DS.popW - 12 - 20, y: 8, width: 14, height: 14)
            addSubview(rightIconView)
        }
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

    private func setHovered(_ on: Bool) {
        layer?.backgroundColor = on ? hoverColor.cgColor : NSColor.clear.cgColor
        titleLabel.textColor   = on ? hoverTextColor : DS.textPrimary
    }

    override func mouseEntered(with e: NSEvent) { setHovered(true)  }
    override func mouseExited(with e: NSEvent)  { setHovered(false) }
    override func mouseUp(with e: NSEvent) {
        setHovered(false)
        onTap?()
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - CalibrationSettingsView
// Matches Stitch HTML: w-[350px], p-4, gap-4 sections,
// flat slider rows (label w-24 | track+thumb | value w-6),
// border-t bottom row: Reset btn (left) | ⌥[ ⌥] pills (right)
// ═══════════════════════════════════════════════════════════

final class CalibrationSettingsView: NSView {

    private let bc: BrightnessController
    private let minSlider = StitchSlider()
    private let maxSlider = StitchSlider()
    private let minLbl    = NSTextField(labelWithString: "20%")
    private let maxLbl    = NSTextField(labelWithString: "80%")

    init(frame: NSRect, controller: BrightnessController) {
        self.bc = controller
        super.init(frame: frame)
        wantsLayer = true
        // Transparent — NSVisualEffectView behind us provides the blur
        layer?.backgroundColor = NSColor.clear.cgColor
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    // Layout constants from Stitch HTML
    // Window: 350px, p-4=16px all sides, gap-4=16px between sections, gap-3=12px between rows
    private func buildLayout() {
        let W:   CGFloat = 350
        let p:   CGFloat = 16   // p-4
        let g4:  CGFloat = 16   // gap-4
        let g3:  CGFloat = 12   // gap-3
        // Label width: w-24 = 96px
        let lblW: CGFloat = 96
        // Value width: w-6 = 24px
        let valW: CGFloat = 26
        // gap-2 = 8px between label | track | value
        let g2: CGFloat = 8
        // Slider row height: 24px (items-center, track 6px centred)
        let rowH: CGFloat = 24
        // Bottom action row height
        let actH: CGFloat = 26
        // Border-t + pt-3 = 12px, mt-2 = 8px
        let actTopSpace: CGFloat = 8 + 1 + 12

        // Build bottom → top (NS coord system)
        var y: CGFloat = p  // bottom p-4 padding

        // ── Bottom row (border-t, justify-between) ────────────
        // Left: Reset to Defaults button  (text-[10px] px-2 py-1 border rounded)
        let resetBtn = SmallOutlineButton(title: "Reset to Defaults",
                                          target: self, action: #selector(resetCalibration))
        resetBtn.frame = NSRect(x: p, y: y, width: 112, height: actH)
        addSubview(resetBtn)

        // Right: ⌥[ and ⌥] pills (px-1.5 py-0.5 bg-white/10 border font-mono text-[10px])
        let pill2 = makePill("⌥ ]")
        pill2.frame = NSRect(x: W - p - 36, y: y + 4, width: 36, height: 18)
        addSubview(pill2)

        let pill1 = makePill("⌥ [")
        pill1.frame = NSRect(x: W - p - 36 - 8 - 36, y: y + 4, width: 36, height: 18)
        addSubview(pill1)

        y += actH + actTopSpace  // border-t separator space

        // Full-width border-t (border-white/5)
        let sep = NSView(frame: NSRect(x: p, y: y - 1, width: W - p*2, height: 1))
        sep.wantsLayer            = true
        sep.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        addSubview(sep)

        // ── Max slider row ────────────────────────────────────
        // (gap-3 above, so skip 12px)
        y += g3
        let trackW = W - p*2 - lblW - g2 - valW - g2

        maxLbl.font        = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        maxLbl.textColor   = DS.textMuted
        maxLbl.alignment   = .right
        maxLbl.stringValue = "\(Int(bc.macBookCalibration.maxBrightness * 100))%"
        maxLbl.frame       = NSRect(x: p + lblW + g2 + trackW + g2, y: y + 5, width: valW, height: 14)
        addSubview(maxLbl)

        maxSlider.frame = NSRect(x: p + lblW + g2, y: y, width: trackW, height: rowH)
        maxSlider.setValue(Double(bc.macBookCalibration.maxBrightness * 100))
        maxSlider.onChanged = { [weak self] v in
            guard let self else { return }
            self.bc.macBookCalibration.maxBrightness = Float(v / 100)
            self.maxLbl.stringValue = "\(Int(v))%"
        }
        addSubview(maxSlider)

        let maxLbl2 = lbl("Maximum (100%)", font: DS.body(11, weight: .medium),
                          color: NSColor(white: 0.80, alpha: 1))
        maxLbl2.frame = NSRect(x: p, y: y + 5, width: lblW, height: 14)
        addSubview(maxLbl2)

        y += rowH

        // ── Min slider row ────────────────────────────────────
        y += g3

        minLbl.font        = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        minLbl.textColor   = DS.textMuted
        minLbl.alignment   = .right
        minLbl.stringValue = "\(Int(bc.macBookCalibration.minBrightness * 100))%"
        minLbl.frame       = NSRect(x: p + lblW + g2 + trackW + g2, y: y + 5, width: valW, height: 14)
        addSubview(minLbl)

        minSlider.frame = NSRect(x: p + lblW + g2, y: y, width: trackW, height: rowH)
        minSlider.setValue(Double(bc.macBookCalibration.minBrightness * 100))
        minSlider.onChanged = { [weak self] v in
            guard let self else { return }
            self.bc.macBookCalibration.minBrightness = Float(v / 100)
            self.minLbl.stringValue = "\(Int(v))%"
        }
        addSubview(minSlider)

        let minLbl2 = lbl("Minimum (0%)", font: DS.body(11, weight: .medium),
                          color: NSColor(white: 0.80, alpha: 1))
        minLbl2.frame = NSRect(x: p, y: y + 5, width: lblW, height: 14)
        addSubview(minLbl2)

        y += rowH

        // gap-4 between sliders section and header
        y += g4

        // ── Description (text-xs text-slate-400) ──────────────
        let desc = NSTextField(wrappingLabelWithString: "Adjust the allowed brightness range for your display.")
        desc.font      = DS.body(11)
        desc.textColor = DS.textMuted
        desc.frame     = NSRect(x: p, y: y, width: W - p*2, height: 14)
        addSubview(desc)
        y += 14 + 4  // mt-1 = 4px

        // ── Section heading (text-sm font-bold) ───────────────
        let heading = lbl("MacBook Brightness Limits",
                          font: DS.body(13, weight: .bold),
                          color: NSColor(white: 0.94, alpha: 1))
        heading.frame = NSRect(x: p, y: y, width: W - p*2, height: 18)
        addSubview(heading)
    }

    // Helpers
    private func lbl(_ s: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: s); f.font = font; f.textColor = color; return f
    }

    // key pill: px-1.5 py-0.5 bg-white/10 border border-white/10 text-[10px] font-mono
    private func makePill(_ text: String) -> NSView {
        let v = NSView()
        v.wantsLayer             = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        v.layer?.cornerRadius    = 4
        v.layer?.borderWidth     = 1
        v.layer?.borderColor     = NSColor(white: 1, alpha: 0.12).cgColor
        let l = NSTextField(labelWithString: text)
        l.font      = .monospacedSystemFont(ofSize: 10, weight: .regular)
        l.textColor = NSColor(white: 0.78, alpha: 1)  // slate-300
        l.alignment = .center
        l.frame     = NSRect(x: 2, y: 2, width: 32, height: 14)
        v.addSubview(l)
        return v
    }

    @objc private func resetCalibration() {
        bc.macBookCalibration = BrightnessCalibration(minBrightness: 0.20, maxBrightness: 0.80)
        minSlider.setValue(20); maxSlider.setValue(80)
        minLbl.stringValue = "20%"; maxLbl.stringValue = "80%"
    }
}

// ─── SmallOutlineButton (matches Stitch 'Reset to Defaults' style) ────────────
// text-[10px] px-2 py-1 rounded border border-white/10 hover:text-slate-200
final class SmallOutlineButton: NSView {
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private let action: Selector
    private weak var target: AnyObject?

    init(title: String, target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        super.init(frame: .zero)
        wantsLayer             = true
        layer?.cornerRadius    = 4
        layer?.borderWidth     = 1
        layer?.borderColor     = NSColor(white: 1, alpha: 0.12).cgColor
        layer?.backgroundColor = NSColor.clear.cgColor

        label.font        = DS.body(10)
        label.textColor   = NSColor(white: 0.60, alpha: 1)  // slate-400/500
        label.alignment   = .center
        label.stringValue = title
        label.frame       = NSRect(x: 4, y: 6, width: 104, height: 14)
        addSubview(label)
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
        label.textColor = NSColor(white: 0.92, alpha: 1)  // hover:text-slate-200
    }
    override func mouseExited(with e: NSEvent) {
        label.textColor = NSColor(white: 0.60, alpha: 1)
    }
    override func mouseUp(with e: NSEvent) {
        NSApp.sendAction(action, to: target, from: self)
    }
}
