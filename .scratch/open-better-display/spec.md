# OpenBetterDisplay Specification

Status: resolved

## Problem Statement

macOS users with multi-monitor setups (such as a MacBook Built-in Display paired with external monitors like the DELL P2217H and DELL U2725QE) lack a built-in way to:

1. Temporarily turn off (disconnect) an individual monitor at the OS level without physically unplugging its display cable or power cord.
2. Adjust the hardware backlight brightness of external third-party monitors alongside the built-in display from a single menu bar popover.
3. Quickly scrub or pick clean, native-aspect-ratio HiDPI/scaled resolutions per display from the menu bar without digging through macOS System Settings.

While BetterDisplay solves this, it is closed-source, freemium/paid (`BetterDisplay Pro`), and packed with dozens of complex submenus (Virtual Screens, Picture-in-Picture, Video Filters, TV controllers, EDID overrides) that clutter the UI when a user only needs display listing, brightness, resolution, and no-unplug display turn-off.

## Solution

Build **OpenBetterDisplay**, a lightweight, open-source (MIT-licensed) native macOS menu bar application with a dark translucent popover modelled directly after BetterDisplay's core display card UI:

- Lists all connected displays (both Enabled Displays and Disconnected Displays) with their human-readable names, display type icon (laptop vs. external monitor), Main Display Badge (`M`) exclusively on the Main Display, and an on/off toggle switch.
- Uses true OS-level display disconnect (`CGSConfigureDisplayEnabled`) to turn off a display so macOS consolidates windows onto remaining active displays and external monitors enter hardware standby, while keeping the turned-off display in the menu bar list so it can be toggled back on at any time.
- Protects the user from losing all visual output by locking the off-toggle on the Main Display and on the last remaining Enabled Display, allowing Main Display status to be transferred to another Enabled Display via its collapsible disclosure drawer, and automatically reconnecting any Disconnected Displays on Mac wake-from-sleep and on app quit.
- Controls display brightness using native backlight control for the Built-in Display, DDC/CI (`IOAVService` I2C VCP `0x10`) hardware backlight control for external monitors, and automatic fallback to software gamma table dimming (`CGSetDisplayTransferByTable`) when a monitor does not support DDC.
- Controls display resolution with a stepped horizontal slider (plus a clickable resolution label dropdown) filtered to clean native-aspect-ratio modes at the current refresh rate (preferring HiDPI modes on 4K/Retina displays and displaying scale percentages such as `2560x1440 · 133%`), previewing live while dragging and committing the mode change on mouse release.

## User Stories

1. As a macOS user, I want OpenBetterDisplay to live in the macOS menu bar with a monitor icon, so that I can access all my displays with a single click from anywhere.
2. As a macOS user, I want the menu bar popover to use a dark, translucent, vibrant HUD aesthetic with rounded display header pills, so that it looks and feels like BetterDisplay's clean native popover.
3. As a macOS user, I want to see a card for every connected display (such as `Built-in Display`, `DELL P2217H`, and `DELL U2725QE`), so that I can identify and manage each screen by its real model name.
4. As a macOS user, I want the Built-in Display to show a laptop icon and external monitors to show an external display icon in their header pill, so that I can distinguish internal and external screens at a glance.
5. As a macOS user, I want to toggle a display OFF using the switch in its header pill, so that macOS disconnects that display at the OS level, moves all windows to my remaining active monitors, and puts the external monitor into no-signal hardware standby without unplugging any cables.
6. As a macOS user, I want a display that I have toggled OFF to remain visible in OpenBetterDisplay's display list (with its toggle in the OFF state and its sliders collapsed), so that I can toggle it back ON whenever I want.
7. As a macOS user, I want toggling a disconnected display back ON to re-enable it in macOS WindowServer and restore its Brightness and Resolution sliders in the popover, so that my multi-monitor workspace returns seamlessly.
8. As a macOS user, I want the current Main Display to display an active `M` badge next to its name and have its turn-off toggle disabled, so that I never accidentally disconnect my primary menu-bar/dock display.
9. As a macOS user, I want every Enabled Display to offer a collapsible disclosure drawer (`⌄`) below its sliders with a `Set as Main Display` row (dimmed `Ⓜ` icon on non-main Enabled Displays; bright active `Ⓜ` icon + `"Main Display"` label on the current Main Display), so that I can transfer Main Display status without cluttering non-main header pills with a Main Display Badge.
10. As a macOS user, I want the turn-off toggle to be disabled whenever only one active display remains on, so that I cannot accidentally turn off all screens and lock myself out of visual output.
11. As a macOS user, I want OpenBetterDisplay to automatically re-enable any turned-off displays when I quit the application, so that I am never left with a persistently disabled display and no menu bar UI to reconnect it.
12. As a macOS user, I want OpenBetterDisplay to automatically re-enable any turned-off displays whenever my Mac wakes from sleep, so that all my monitors come back online predictably at the start of a session.
13. As a macOS user, I want a "Reconnect All Displays" action in the popover footer whenever one or more displays are turned off, so that I can bring every disconnected screen back online with a single click.
14. As a macOS user, I want a Brightness slider (`0%`–`100%`) on every active display card showing the current brightness percentage, so that I can adjust brightness smoothly from the menu bar.
15. As a macOS user, I want the Brightness slider for my Built-in Display to adjust the native Apple panel backlight (`DisplayServices`), so that it changes real hardware panel luminance and stays in sync with macOS brightness changes.
16. As a macOS user, I want the Brightness slider for my external monitors (such as Dell monitors on Apple Silicon) to adjust the monitor's physical backlight over DDC/CI (`IOAVService` I2C VCP `0x10`), so that the monitor's actual hardware backlight dims rather than just washing out black levels.
17. As a macOS user, I want OpenBetterDisplay to automatically fall back to software gamma dimming (`CGSetDisplayTransferByTable`) if an external monitor does not respond to DDC/CI commands, so that brightness adjustment still works on every monitor.
18. As a macOS user, I want my per-display brightness level to be remembered across app restarts and hotplug events, so that I don't have to re-adjust brightness every time I launch the app.
19. As a macOS user, I want a Resolution slider on every active display card showing the resolution and scale percentage (such as `1512x982`, `1920x1080`, or `2560x1440 · 133%`), so that I can see and adjust my UI scaling at a glance.
20. As a macOS user, I want the Resolution slider stops to be filtered to clean modes matching my display's native aspect ratio and current refresh rate (preferring HiDPI/Retina modes on 4K and Retina panels), so that the slider only steps through crisp, usable resolutions.
21. As a macOS user, I want dragging the Resolution slider to preview the target `<Width>x<Height> · <Scale>%` label live while I drag and only apply the display mode switch when I release the mouse button, so that my screen does not repeatedly flash black while scrubbing the slider.
22. As a macOS user, I want to be able to click the resolution text label (`2560x1440 · 133%`) to open a dropdown menu of the available resolutions for that display, so that I can jump directly to a specific resolution without dragging the slider.
23. As a macOS user, I want OpenBetterDisplay to detect in real time when monitors are physically plugged in, unplugged, or reconfigured, so that the menu bar list always reflects my current hardware setup.
24. As a macOS user, I want a clean bottom bar in the popover with "Launch at Login", "Reconnect All Displays" (when applicable), and "Quit OpenBetterDisplay", without any bloatware menus or Pro upsell banners.
25. As an open-source contributor or user on GitHub, I want to build and package `OpenBetterDisplay.app` from the terminal with a single command (and open the project in Xcode), under an MIT License with a clear `README.md` and `.gitignore` that excludes proprietary reference DMGs.

## Implementation Decisions

### 1. Deep Module Architecture & Single Seam

The system is divided into three layers with a single primary seam (`DisplayDriver`) between domain coordination and macOS system calls:

- **`DisplayCoordinator` (Deep Domain Module)**:
  - Owns the canonical observable state consumed by the UI and tests.
  - Maintains a registry of both **active online displays** and **app-disconnected displays**. Because disabling a display via SkyLight (`CGSConfigureDisplayEnabled`) causes macOS to remove or deactivate that display from standard active display queries, `DisplayCoordinator` caches the metadata of any display it disconnects (`DisplayDescriptor`) so the display remains in the user's list in the `OFF` state until toggled back `ON`, woken from sleep, or restored on quit.
  - Enforces all safety invariants:
    - `canToggleOff(displayID)` is `false` if `display.isMain == true` OR if the count of currently enabled displays is `<= 1`.
    - `setMainDisplay(displayID)` is only enabled for active, non-main displays; transferring Main Display status updates `isMain` so the previous Main Display can now be toggled off.
  - Debounces/throttles hardware DDC brightness writes while keeping slider state instantaneous, and routes brightness commands through the display's capability tier (`nativeAppleBacklight` → `hardwareDDC` → `softwareGamma`).
  - Separates resolution **preview state** (`previewModeID` updated on slider drag) from **committed state** (`commitResolution` called on slider drag end or dropdown click).
  - Handles lifecycle hooks (`handleSystemWake()` and `handleAppWillTerminate()`), iterating through all currently disabled display IDs and re-enabling them (plus resetting any custom software gamma tables on quit).

- **`DisplayDriver` (The Seam Interface)**:

  ```swift
  public protocol DisplayDriver: Sendable {
      func fetchOnlineDisplays() -> [RawDisplayInfo]
      func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) throws
      func setMainDisplay(_ displayID: UInt32) throws
      func getBrightness(_ displayID: UInt32) -> BrightnessReading
      func setBrightness(_ displayID: UInt32, level: Double) -> BrightnessBackendUsed
      func setDisplayMode(_ displayID: UInt32, modeID: Int32) throws
      func resetSoftwareGamma()
  }
  ```

- **`MacOSDisplayDriver` (Production Adapter)**:
  - **Display Discovery & Naming**:
    - Uses `CGSGetDisplayList` / `CGGetOnlineDisplayList` to discover all connected display IDs.
    - Resolves human-readable names (`"Built-in Display"`, `"DELL P2217H"`, `"DELL U2725QE"`) via `CoreDisplay_DisplayCreateInfoDictionary` (`DisplayProductName`), `NSScreen.screens` (`localizedName`), and IOKit EDID descriptor strings (`IODisplayConnect`), falling back to vendor/model hex only if unnamed.
    - Reads `CGDisplayIsBuiltin`, `CGDisplayIsMain`, `CGDisplayIsActive`, `CGDisplayVendorNumber`, `CGDisplayModelNumber`, and `CGDisplaySerialNumber`.
  - **OS-Level Display Turn-Off & Reconnect**:
    - Dynamically resolves `CGSConfigureDisplayEnabled` from `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` via `dlsym`.
    - Wraps calls in a CoreGraphics transaction: `CGBeginDisplayConfiguration(&config)` → `CGSConfigureDisplayEnabled(config, displayID, enabled)` → `CGCompleteDisplayConfiguration(config, .forSession)`.
  - **Main Display Promotion (`M`)**:
    - Wraps `CGBeginDisplayConfiguration(&config)` → `CGConfigureDisplayOrigin(config, targetDisplayID, 0, 0)` (and adjusts other displays' relative origins so layout doesn't overlap) → `CGCompleteDisplayConfiguration(config, .forSession)`.
  - **Brightness Control**:
    - **Tier 1 (Built-in / Apple Displays)**: Dynamically resolves `DisplayServicesCanChangeBrightness`, `DisplayServicesGetBrightness`, and `DisplayServicesSetBrightness` from `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices`.
    - **Tier 2 (External Monitors via Apple Silicon DDC/CI)**: Matches `DCPAVServiceProxy` in the IORegistry (`IOServiceMatching("DCPAVServiceProxy")`) corresponding to the display, creates an `IOAVServiceRef` via `IOAVServiceCreateWithService`, and sends DDC/CI VCP `0x10` (Luminance) packets over I2C (`chipAddress: 0x37`, `dataAddress: 0x51`) with standard XOR checksum via `IOAVServiceWriteI2C` and reads initial brightness via `IOAVServiceReadI2C`.
    - **Tier 3 (Automatic Fallback — Software Gamma Dimming)**: If neither Tier 1 nor Tier 2 succeeds for a display, scales the RGB gamma transfer table via `CGSetDisplayTransferByTable(displayID, ...)` from `[0, 1]` down to `[0, max(0.08, level)]` so the display never becomes completely unreadable at `0%`.
  - **Resolution Enumeration, Filtering & Mode Switching**:
    - Queries modes via `CGDisplayCopyAllDisplayModes(displayID, [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue])` and SkyLight's `CGSGetNumberOfDisplayModes` / `CGSGetDisplayModeDescriptionOfLength` / `CGSGetCurrentDisplayMode`.
    - Determines the display's native pixel dimensions (highest 1x pixel width/height) and native aspect ratio.
    - Filters modes to those matching the native aspect ratio (within tolerance) and current refresh rate. If the display supports HiDPI (backing scale factor `2x` modes exist), filters to HiDPI modes so text stays sharp; otherwise uses standard `1x` modes (e.g., for `DELL P2217H` 1080p).
    - Computes the scale percentage displayed in the UI (`2560x1440 · 133%` on a 4K 3840x2160 monitor, and `1920x1080` without redundant percentage when at 100% 1x native).
    - Applies mode switches via `CGBeginDisplayConfiguration` + `CGConfigureDisplayWithDisplayMode` / `CGSConfigureDisplayMode` + `CGCompleteDisplayConfiguration`.

### 2. Menu Bar & Popover UI Module

- Uses an `NSStatusItem` in the macOS system status bar with an `NSPopover` backed by a dark `NSVisualEffectView` (`hudWindow` / `popover` material, vibrant dark appearance) hosting the SwiftUI view hierarchy.
- Each Display Card renders:
  - **Header Pill**: Rounded dark translucent container with display icon (`laptopcomputer` or `display`), display name, Main Display Badge (`M`, shown exclusively on the Main Display — omitted on non-main Enabled Displays and Disconnected Displays), and custom capsule toggle switch on the right (disabled with tooltip when `isMain` or last Enabled Display).
  - **Controls Area (visible on Enabled Displays)**:
    - `Brightness` header row with current `<N>%` and horizontal slider with sun icon (`sun.max.fill`).
    - `Resolution` header row with clickable `<Width>x<Height>` (or `<Width>x<Height> · <Scale>%`) menu trigger and stepped horizontal slider with resolution icon (`arrow.up.left.and.arrow.down.right`).
    - Collapsible single-open accordion disclosure chevron (`⌄` / `⌃`, collapsed by default; auto-collapses on disconnect, unplug, or popover close, stays open in place when `Set as Main Display` is clicked) revealing a footer-styled Main Display row: dimmed `Ⓜ` icon + clickable `"Set as Main Display"` on non-main Enabled Displays, and bright active `Ⓜ` icon + non-interactive `"Main Display"` on the current Main Display.
- **Footer Section**:
  - Shows a prominent `Reconnect All Displays` button whenever any display is currently toggled OFF.
  - Includes `Launch at Login` toggle (`SMAppService.mainApp`) and `Quit OpenBetterDisplay` action.

### 3. Open-Source Repository & Build Packaging

- Structured as a Swift Package (`Package.swift`) with library target `OpenBetterDisplayCore` (containing `DisplayCoordinator`, `DisplayDriver`, models, and resolution/brightness logic), executable target `OpenBetterDisplay`, and test target `OpenBetterDisplayTests`.
- Includes `scripts/build-app.sh` and a `Makefile` (`make app`, `make test`, `make run`) that compiles the binary and packages a complete, ad-hoc code-signed `OpenBetterDisplay.app` bundle (`Contents/Info.plist` with `LSUIElement = true`, `Contents/MacOS/OpenBetterDisplay`).
- Includes `LICENSE` (MIT), `README.md`, and `.gitignore` (explicitly ignoring `*.dmg`, `.build/`, `build/`, and `.DS_Store`).

## Testing Decisions

- **Philosophy**: Tests verify observable behavior at the `DisplayCoordinator` interface across the `DisplayDriver` seam — never private implementation details.
- **Module Under Test**: `OpenBetterDisplayCore` (`DisplayCoordinator` + resolution/mode filtering + brightness fallback + safety state machine) using `FakeDisplayDriver`.
- **Behavioral Test Suite Coverage**:
  1. **Multi-Display Enumeration & Sorting**: Built-in display and external monitors (`Built-in Display`, `DELL P2217H`, `DELL U2725QE`) appear with accurate names, icons, main-display status, brightness, and resolution stops.
  2. **OS-Level Display Turn-Off & Retention**: Toggling a non-main display OFF invokes `driver.setDisplayEnabled(id, enabled: false)` and retains the display in `coordinator.displays` with `isEnabled == false` even after `driver.fetchOnlineDisplays()` stops returning it as active.
  3. **Reconnecting a Disconnected Display**: Toggling a disabled display ON invokes `driver.setDisplayEnabled(id, enabled: true)` and restores its active controls.
  4. **Main Display (`M`) Guardrail & Transfer**: The Main Display cannot be toggled off (`canToggleOff == false`). Calling `setMainDisplay(otherID)` promotes `otherID` to Main Display (`isMain == true`, `canToggleOff == false`) and unlocks the previous Main Display (`isMain == false`, `canToggleOff == true`).
  5. **Last Active Display Guardrail**: When 2 of 3 displays are turned off, the final remaining active display has `canToggleOff == false` regardless of whether it was originally Main.
  6. **Auto-Restore on App Quit & Sleep/Wake**: Calling `handleAppWillTerminate()` or `handleSystemWake()` automatically re-enables all disconnected displays and resets software gamma.
  7. **Brightness Routing & Fallback**: Built-in display uses native backlight; external DDC-capable display uses hardware DDC; external non-DDC display falls back to software gamma dimming and persists user brightness preferences per display.
  8. **Resolution Filtering & Live Preview vs. Commit**: Modes are filtered to native aspect ratio and current refresh rate (preferring HiDPI on 4K/Retina panels), scale percentages match expected labels (e.g., `2560x1440 · 133%` on 3840x2160), dragging updates the preview label without calling `driver.setDisplayMode`, and releasing commits the mode change once.

## Out of Scope

- Virtual screens / dummy display creation (`CGVirtualDisplay`)
- Picture-in-Picture (PiP) and Display Streaming (`ScreenCaptureKit`)
- Hardware volume / audio DDC control (`Volume` slider)
- EDID overrides, custom refresh rate overclocking, and ColorSync ICC profile editing
- TV network/CEC controllers (Tizen, LG WebOS, Philips TV, HDMI-CEC)
- Global keyboard shortcut interception requiring Accessibility / Input Monitoring permissions
- Commercial licensing / Paddle activation (`BetterDisplay Pro`)

## Further Notes

- Verified on the target host (`macOS 26.5.1`, `arm64`, Apple Swift `6.3.3`).
- Private SkyLight (`CGSConfigureDisplayEnabled`, `CGSGetNumberOfDisplayModes`, `CGSGetDisplayModeDescriptionOfLength`, `CGSConfigureDisplayMode`), DisplayServices (`DisplayServicesGetBrightness`, `DisplayServicesSetBrightness`), CoreDisplay (`CoreDisplay_DisplayCreateInfoDictionary`), and IOMobileFramebuffer (`IOAVServiceCreateWithService`, `IOAVServiceReadI2C`, `IOAVServiceWriteI2C`) symbols are loaded dynamically via `dlopen`/`dlsym` so the Swift package compiles cleanly with standard public macOS SDK headers without requiring fragile private `.tbd` stub files.
