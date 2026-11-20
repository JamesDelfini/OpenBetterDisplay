# OpenBetterDisplay

Lightweight open-source replacement for BetterDisplay on macOS: manage built-in and external monitors from the menu bar — OS-level display disconnect, Apple Silicon DDC/CI hardware brightness, HiDPI resolution scaling, and Main Display switching, with macOS private display APIs documented.

## Features

- **Dark Translucent Menu Bar Popover:** Native `NSVisualEffectView` (`hudWindow` / vibrant dark) menu bar popover listing every connected monitor (both **Enabled Displays** and **Disconnected Displays**) with human-readable model names (`CoreDisplay` → `NSScreen` → IOKit EDID fallback), laptop vs. external monitor icons, and the **Main Display Badge** (`M`) exclusively on the current **Main Display**.
- **OS-Level Display Disconnect & Safety Guardrails:** Toggle individual external or built-in displays off and back on at the macOS WindowServer level (`CGSConfigureDisplayEnabled`) so macOS consolidates windows onto remaining **Enabled Displays** and external monitors enter hardware standby while staying listed in the popover.
  - Locks the off-toggle on the **Main Display** and on the last remaining **Enabled Display** so you can never lock yourself out of visual output.
  - Surfaces a **Reconnect All Displays** button whenever one or more **Disconnected Displays** exist.
  - Automatically reconnects all **Disconnected Displays** on Mac wake-from-sleep and on app quit.
- **Main Display Switching:** Every **Enabled Display** includes a collapsible disclosure drawer (`⌄`) exposing **Set as Main Display** (`CGConfigureDisplayOrigin`), closing the popover cleanly before macOS relocates the menu bar and Dock.
- **3-Tier Hardware & Fallback Brightness Control:**
  - **Tier 1 — Native Apple Backlight (`DisplayServices`):** Controls the Built-in Display backlight and stays in sync with macOS brightness keys.
  - **Tier 2 — Apple Silicon DDC/CI (`IOAVService` I2C VCP `0x10`):** Controls physical external monitor backlight over `DCPAVServiceProxy` with EDID / `IODisplayLocation` matching, leading+trailing write throttling, and transient-failure cooldown recovery.
  - **Tier 3 — Software Gamma Fallback (`CGSetDisplayTransferByTable`):** Automatic fallback with a safe minimum luminance floor (`0.08`) when a monitor does not respond to DDC/CI, restored cleanly on quit.
  - Persists last-set brightness per display across app restarts and hotplug events.
- **HiDPI Resolution Slider & Mode Picker:** Filters modes to the display's native aspect ratio and current refresh rate (preferring HiDPI modes on Retina/4K displays and standard modes on 1x panels), previews `<Width>x<Height> · <Scale>%` live while dragging without flickering, commits once on mouse release, and lets you click the resolution label to jump directly via a dropdown menu.
- **Zero Bloat:** Includes **Launch at Login** (`SMAppService`) and **Quit OpenBetterDisplay** — no virtual screens, PiP, TV controllers, or Pro upsells.

## Requirements

- macOS 14.0+ (verified on Apple Silicon / macOS 26; Intel supported with software gamma fallback for non-`IOAVService` external displays)
- Swift 5.9+ / Xcode 15+

## Building & Running

### From the Command Line

Build and package an ad-hoc signed `build/OpenBetterDisplay.app`:

```bash
make app
# or directly:
./scripts/build-app.sh
```

Build and launch immediately:

```bash
make run
```

### In Xcode

Open `Package.swift` directly in Xcode:

```bash
xed .
```

Select the `OpenBetterDisplay` scheme and press **Run** (`Cmd+R`), or press **Test** (`Cmd+U`) to run `OpenBetterDisplayTests`.

## Development & Verification

All targets auto-isolate Swift/Clang module caches per worktree so concurrent builds and sandboxed environments stay clean:

```bash
make check          # Strict swift-format lint, -warnings-as-errors build, hygiene guards, and test suite
make test           # Full verbose XCTest output
make test-quiet     # Concise suite summary (full output on failure)
make format         # Auto-format Sources/, Tests/, and Tools/ using .swift-format
make preview        # Render a 3-display popover snapshot to /tmp/openbetterdisplay-preview.png
make install-hooks  # Install pre-commit hook running `make check`
```

## Architecture & Documentation

OpenBetterDisplay uses a single primary seam (`DisplayDriver`) separating domain state from macOS system frameworks, allowing the behavioral test suite (`OpenBetterDisplayTests`) to exercise every guardrail, brightness fallback, persistence rule, and mode filter deterministically without hardware side effects:

```text
Sources/
├── OpenBetterDisplayCore/   # DisplayCoordinator, DisplayDriver, MacOSDisplayDriver, AppleSiliconDDCClient,
│                            # DDCProtocol, DisplayModeFilter, BrightnessPersistence, BrightnessWriteScheduler
├── OpenBetterDisplayUI/     # SwiftUI HUD popover, display cards, sliders, disclosure drawer
└── OpenBetterDisplay/       # NSStatusItem, vibrant NSPopover lifecycle, sleep/wake & quit hooks
Tools/
└── PopoverPreview/          # Headless offscreen renderer for UI verification (`make preview`)
Tests/
└── OpenBetterDisplayTests/  # Behavioral tests across DisplayDriver + DDC/SkyLight protocol tests
```

All private macOS symbols (`SkyLight`, `DisplayServices`, `CoreDisplay`, and `IOKit` `IOAVService*`) are loaded dynamically at runtime via `dlopen`/`dlsym`, so the project compiles cleanly against public macOS SDK headers with zero private `.tbd` stubs.

- [docs/macos-private-apis.md](docs/macos-private-apis.md) — Verified Apple Silicon (`M4` / macOS 26) IORegistry topology, `IOAVService*` calling conventions, DDC/CI VCP `0x10` wire packets & checksums, SkyLight 212-byte mode description layout, and `NSPopover` display-reconfiguration invariants.
- [GLOSSARY.md](GLOSSARY.md) — Canonical domain vocabulary (**Main Display**, **Main Display Badge**, **Enabled Display**, **Disconnected Display**).
- [CODING_STANDARDS.md](CODING_STANDARDS.md) — Review standards complementing `make check`.

## License

Released under the [MIT License](LICENSE).
