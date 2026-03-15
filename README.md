# FusionNotch

A lightweight macOS menu bar utility for MacBook Pro / Air devices with a notch. Hover over the notch to reveal a live system stats panel that expands seamlessly from the hardware cutout.

![FusionNotch panel](screenshot/Screenshot%202026-03-15%20at%203.13.47%20PM.png)

## Features

- **Hover-to-reveal** — panel appears when you move the cursor to the notch area, disappears when you move away
- **Live metrics** — RAM usage · Battery status · Network upload/download speed · CPU temperature
- **Notch-native design** — pure black panel anchored at the screen top so it looks like the notch physically expanding
- **Spring animation** — smooth organic open/close with a spring physics curve
- **Lightweight** — no Electron, no heavy frameworks; pure Swift + SwiftUI + AppKit
- **Launch at Login** — optional, toggled from the menu bar

## Requirements

| | |
|---|---|
| macOS | 13 Ventura or later (tested on macOS 26) |
| Hardware | MacBook Pro / Air with notch (M1 Pro/Max/Ultra, M2, M3, M4 series) |
| Xcode | Not required to run — only needed to build from source |

## Installation

### Pre-built binary
1. Download `FusionNotch.app` from [Releases](../../releases)
2. Move it to `/Applications`
3. Open it — macOS will ask to remove the quarantine attribute the first time:
   ```
   xattr -cr /Applications/FusionNotch.app
   ```
4. Grant **Accessibility access** when prompted (required for global mouse tracking)

### Build from source
```bash
git clone https://github.com/rutvik106/FusionNotch.git
cd FusionNotch
bash build.sh
cp -r build/FusionNotch.app /Applications/
xattr -cr /Applications/FusionNotch.app
open /Applications/FusionNotch.app
```

> `build.sh` compiles with `swiftc` and ad-hoc signs the app. Xcode is **not** required.

## Accessibility Permission

FusionNotch uses `NSEvent.addGlobalMonitorForEvents` to track mouse position globally. macOS requires Accessibility access for this.

1. On first launch a system dialog will appear — click **Open System Settings**
2. In **Privacy & Security → Accessibility**, enable FusionNotch
3. The menu bar icon changes from `⚠` to `●` when active

> Every time you rebuild from source the binary hash changes, so macOS will ask you to re-grant access. This is expected behaviour for ad-hoc-signed binaries.

## Uninstall

```bash
pkill FusionNotch
rm -rf /Applications/FusionNotch.app
```

## How it works

| Component | Role |
|---|---|
| `NotchTracker` | Detects the notch geometry via `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Runs a global mouse monitor to fire hover enter/exit callbacks. |
| `OverlayWindowController` | Manages a borderless `NSPanel` at `popUpMenuWindow` level (above the menu bar). Positions the panel top at `screen.frame.maxY` so the black background merges with the physical notch. |
| `NotchPanelView` | SwiftUI view. `UnevenRoundedRectangle` with 0-radius top corners (flush with notch) and 26-radius bottom corners. Animates with `scaleEffect y: 0→1` anchored at `.top` using a spring curve. |
| `MetricsEngine` | Polls RAM (`host_statistics64`), battery (`IOPSCopyPowerSourcesInfo`), network (`getifaddrs`), and temperature (SMC via `IOKit`) on a 1-second timer. |

## Contributing

PRs welcome. Open an issue first for anything larger than a bug fix.

## License

MIT — see [LICENSE](LICENSE)
