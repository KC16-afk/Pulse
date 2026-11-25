# Pulse

A native macOS menu bar system monitor built with Swift, AppKit, and SwiftUI.

## What it does

- **Live CPU sparkline in the menu bar** — a retina-crisp, color-changing graph (green → amber → red) that updates every second. Hover for a tooltip with CPU and memory usage.
- **Click the sparkline** to open a frosted-glass popover with:
  - Animated CPU chart plus user/system/idle breakdown
  - Memory ring with used/total figures
  - Live network download/upload rates
  - Battery level and charging state
  - Top 5 CPU-consuming processes with bars
- **Quit Pulse** button in the popover footer.

The app runs as an accessory (menu bar only — no Dock icon or main window).

## Build & run

Requires macOS 13+ and a Swift toolchain (Xcode or Command Line Tools).

```bash
cd Pulse
./build.sh          # builds Pulse.app
./build.sh --run    # builds and launches it
```

You can also just double-click `Pulse.app` after building.

## Project layout

```
Pulse/
├── Sources/Pulse/
│   ├── main.swift              # NSApplication entry point
│   ├── AppDelegate.swift       # status item + popover wiring
│   ├── SystemMonitor.swift     # CPU / memory / network / battery / process sampling
│   ├── MenuBarRenderer.swift   # draws the menu bar sparkline into an NSImage
│   ├── ContentView.swift       # SwiftUI popover UI
│   └── Formatters.swift        # byte/rate/percent formatting
├── build.sh                    # swiftc build + .app bundle + ad-hoc codesign
└── Pulse.app                   # built product (generated)
```

## Notes

- Stats are sampled with `host_statistics` / `host_statistics64`, `getifaddrs`, IOKit power sources, and libproc.
- The binary is ad-hoc signed so it launches without Gatekeeper prompts on a locally built machine.
