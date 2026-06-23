# Tandem

A lightweight macOS menu bar app that keeps your MacBook and external monitors in sync — one slider, every screen.

![macOS](https://img.shields.io/badge/macOS-12.0+-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-green)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

## What it does

- **Unified brightness control** — change brightness once, every connected display follows.
- **Native F1 / F2 keys** — the keys you already use, now wired to your external monitors too.
- **Custom shortcuts** — Option + [ / ] work from any keyboard (mechanical, external, USB).
- **Real DDC where available** — backlight control via `m1ddc` on USB-C / DisplayPort displays.
- **Software dim fallback** — GPU gamma scaling automatically takes over when DDC isn't supported (HDMI, docks, adapters). Survives fullscreen, Spaces, and screen recording.
- **Per-display calibration** — each monitor gets its own min/max brightness range.
- **Auto-detect** — hotplug a monitor and Tandem syncs it within a second, no clicks.
- **Native macOS UI** — system fonts, system colors, light/dark mode, no custom chrome.

## Install

### 1. Install m1ddc (optional but recommended)

```bash
brew install m1ddc
```

m1ddc enables real backlight control over USB-C and DisplayPort. Without it, Tandem still works — it falls back to software gamma dimming for every external display.

### 2. Download and run

Grab `Tandem.dmg` from [Releases](../../releases), drag the app into `/Applications`, then strip the quarantine attribute so macOS doesn't block it:

```bash
xattr -cr "/Applications/Tandem.app"
```

Open Tandem from Applications. A ☀ icon appears in your menu bar.

## Usage

- **F1 / F2** — adjust brightness; externals follow.
- **Option + [ / ]** — same, works on any keyboard.
- **Menu bar slider** — drag for fine control.
- **Calibration Settings…** — per-display min/max ranges.

## Connection support

| Connection | Mode | Notes |
|------------|------|-------|
| USB-C / Thunderbolt | DDC (real backlight) | Best option. |
| DisplayPort | DDC (real backlight) | Direct or via USB-C → DP adapter. |
| HDMI direct | Software dim (gamma) | Apple Silicon doesn't support DDC over native HDMI. |
| HDMI via dock | Software dim (gamma) | Most docks block DDC; Tandem detects this and falls back automatically. |
| Mixed setup | Per-display routing | Each display picks the best available mode independently. |

You can see the chosen mode for each display in the menu bar dropdown — `DDC` (green) or `Software` (yellow).

## Calibration

Open ☀ → **Calibration Settings…** for per-display sliders:

- **MacBook Display** — defaults 20% min, 80% max. Prevents the built-in display from going pitch black or blinding-white at slider extremes.
- **Each external** — defaults 20% min, 100% max. Raise the minimum if 0% feels too dim; lower the maximum to cap the display's brightness ceiling.

Calibration is per-display, persisted across reboots, and identified by EDID (vendor + model + serial), so disconnecting and reconnecting the same monitor preserves its settings.

## Troubleshooting

**"App is damaged" error:**
```bash
xattr -cr "/Applications/Tandem.app"
```

**External monitor isn't responding:**
1. Open the menu bar dropdown. Confirm the display is listed with a mode badge.
2. If you expect DDC but see `Software` — DDC isn't available on that connection (HDMI, dock, or unsupported monitor). The software fallback works.
3. If the display doesn't appear at all — unplug and replug; Tandem detects hotplug within a second.

**Gamma stays applied after a force quit:** Relaunch Tandem, set the slider to 100%, then quit cleanly. Or sleep + wake the Mac.

## Build from source

```bash
git clone https://github.com/aditya-madaan/BrightnessSync-Mac.git
cd BrightnessSync-Mac
./build.sh
```

The built app lands in `build/Tandem.app`.

## Project structure

```
.
├── BrightnessSyncMac/
│   ├── main.swift                     App entry point
│   ├── AppDelegate.swift              Menu bar + popover + settings UI
│   ├── BrightnessController.swift     Sync logic, per-display calibration, routing
│   ├── DDCControl.swift               m1ddc wrapper + probe
│   ├── SoftwareDimController.swift    GPU gamma fallback
│   ├── DisplayManager.swift           Display enumeration
│   ├── KeyboardShortcutManager.swift  Global hotkeys via CGEventTap
│   └── Info.plist
├── build.sh                           Single-command build
└── README.md
```

## Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon (M1, M2, M3, M4)
- `m1ddc` (optional, enables real DDC: `brew install m1ddc`)

## License

MIT — see [LICENSE](LICENSE).

## Credits

- [m1ddc](https://github.com/waydabber/m1ddc) — DDC control on Apple Silicon
