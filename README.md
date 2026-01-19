# BrightnessSync Mac ☀️

A lightweight macOS menu bar app to control your MacBook and external monitor brightness together with calibrated sync.

![macOS](https://img.shields.io/badge/macOS-12.0+-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3-green)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

## Features

- ☀️ **Unified brightness control** - Single slider syncs brightness across all displays
- ⌨️ **Keyboard shortcuts** - Option+F1/F2 to quickly adjust brightness
- 🔐 **Auto-Permissions** - Prompts for Accessibility access automatically
- 🎚️ **Calibrated sync** - Maps brightness levels so displays match visually
- 💡 **Built-in display support** - Native brightness control via DisplayServices
- 🖥️ **External monitor support** - DDC/CI via m1ddc for hardware brightness
- ⚡ **Lightweight** - Pure Swift, minimal memory footprint

## Installation

### 1. Download DMG
Download the latest release from the [Releases](../../releases) page.

### 2. Install
Open `BrightnessSyncMac.dmg` and drag the app to your Applications folder.

### 3. Bypass "App is Damaged" Warning
Since this app is not signed with a paid Apple Developer ID, macOS (Gatekeeper) may show an error that **"BrightnessSync Mac is damaged and can't be opened."**

To fix this, open Terminal and run this command:
```bash
xattr -cr "/Applications/BrightnessSync Mac.app"
```
Then you can run the app normally!

## Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon Mac (M1/M2/M3)
- `m1ddc` for external monitor control:
  ```bash
  brew install m1ddc
  ```

## Usage

1. **Run the app** - A ☀️ icon appears in your menu bar
2. **Grant Permissions** - The app will ask for Accessibility access (needed for keyboard shortcuts)
3. **Use the Slider** - Click the icon to adjust brightness
4. **Use Shortcuts** - ⌥F1 (decrease) / ⌥F2 (increase)

## How It Works

- **MacBook display**: Uses Apple's DisplayServices private framework
- **External monitors**: Uses [m1ddc](https://github.com/waydabber/m1ddc) for DDC/CI control
- **Permissions**: Polling mechanism detects when Accessibility is granted to enable shortcuts

## Project Structure

```
BrightnessSyncMac/
├── BrightnessSyncMac/
│   ├── main.swift              # App entry point
│   ├── AppDelegate.swift       # Menu bar UI + logic
│   ├── BrightnessController.swift  # Brightness management
│   ├── DDCControl.swift        # External monitor via m1ddc
│   └── DisplayManager.swift    # Display enumeration
├── build.sh                    # Build script
└── README.md
```

## License

MIT License - see [LICENSE](LICENSE)
