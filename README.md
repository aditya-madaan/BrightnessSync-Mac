# BrightnessSync

A lightweight macOS menu bar app to control your MacBook and external monitor brightness together.

## Features

- 🌞 **Unified brightness control** - Single slider syncs brightness across all displays
- ⌨️ **Keyboard shortcuts** - Option+F1/F2 to quickly adjust brightness
- 💡 **Built-in display support** - Native brightness control via DisplayServices
- 🖥️ **External monitor support** - DDC/CI via m1ddc for hardware brightness
- ⚡ **Lightweight** - Minimal memory footprint, pure Swift
- 🎨 **Native UI** - Blends seamlessly with macOS

## Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon Mac (M1/M2/M3)
- `m1ddc` for external monitor control: `brew install m1ddc`

## Quick Start

```bash
# Run the app
/Users/adityamadaan/.gemini/antigravity/scratch/BrightnessSync/build/BrightnessSync.app/Contents/MacOS/BrightnessSync
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌥ Option + F1 | Decrease brightness by 10% |
| ⌥ Option + F2 | Increase brightness by 10% |

> **Note**: Keyboard shortcuts require Accessibility permissions. Go to **System Settings → Privacy & Security → Accessibility** and add BrightnessSync.

## Building from Source

```bash
cd /Users/adityamadaan/.gemini/antigravity/scratch/BrightnessSync

# Compile
swiftc -sdk $(xcrun --show-sdk-path) \
       -target arm64-apple-macosx12.0 \
       -o build/BrightnessSync.app/Contents/MacOS/BrightnessSync \
       BrightnessSync/*.swift \
       -framework AppKit \
       -framework IOKit \
       -framework CoreGraphics \
       -framework Carbon
```

## Usage

1. **Click the ☀️ icon** in the menu bar
2. **Drag the slider** to adjust brightness on all displays
3. **Use keyboard shortcuts** (⌥F1/⌥F2) for quick adjustments

## How It Works

- **MacBook display**: Uses DisplayServices private framework
- **External monitors**: Uses `m1ddc` command-line tool (DDC/CI protocol)

## Troubleshooting

### Keyboard shortcuts not working?
Grant Accessibility permissions: **System Settings → Privacy & Security → Accessibility**

### External monitor brightness not changing?
1. Ensure `m1ddc` is installed: `brew install m1ddc`
2. Check if your monitor supports DDC: `m1ddc display list`

## License

MIT License
