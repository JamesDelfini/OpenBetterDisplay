# Display Mode Browser, Refresh Rate Picker & Brightness Hotkeys

Status: resolved

## Problem Statement

Users running macOS with built-in and external monitors face three daily friction points in OpenBetterDisplay:

1. **Limited Display Mode visibility and filtering**: A single resolution slider hides critical mode attributes—such as whether a mode is **HiDPI** or **LoDPI**, its aspect ratio, refresh rate, and color depth (`10bit` vs `8bit`)—and provides no way to filter across hundreds of macOS-exposed modes or save frequently used **Display Modes** for one-click switching.
2. **No Refresh Rate switching**: Users on 120Hz or variable-refresh monitors cannot quickly view or switch refresh rates (including **Variable Refresh Rate** ranges and hardware-exposed **NTSC Refresh Rates**) for their current logical resolution without leaving the menu bar.
3. **No global Brightness Hotkeys for external displays**: Pressing `F1` / `F2` (or **Brightness Hotkeys** `☀️-` / `☀️+`) only adjusts the **Built-in Display** via macOS, leaving external monitors untouched or showing the macOS unavailable HUD. Moreover, users who flip macOS between media **Brightness Hotkeys** and standard `F1`–`F12` function keys have no in-app visibility into why `F1`/`F2` vs `Fn+F1`/`Fn+F2` behaves differently or whether Accessibility access is active.

## Solution

Upgrade OpenBetterDisplay's menu bar popover and core coordinator with three integrated, bloat-free capabilities while keeping the compact **Brightness** slider on every **Enabled Display** card:

- **Collapsible Display Mode Browser & Filter**: Replace the old `Resolution` slider with a collapsible **Display Mode** pill directly on each **Enabled Display** card (showing the active resolution summary when collapsed). Expanding it reveals up to 5 per-display **Favorite Modes** (`Manage...` + right-click context menu), **Default Mode** (`★`) and **Native Mode** (`≡`) quick rows, and a scrollable, filterable list of all safe `>= 720p` macOS-exposed **Display Modes** with `✦` (**HiDPI**), aspect ratio, refresh rate, and color depth badges plus an interactive `Filter...` chip panel (`⇧ Shift` multi-select, `Show All`, `Reset Default`).
- **Collapsible Refresh Rate Picker**: Add a collapsible **Refresh Rate** pill on each **Enabled Display** card (showing the active refresh rate summary when collapsed) that lists **Variable Refresh Rate** modes, standard integer rates, and macOS-exposed **NTSC Refresh Rates** for the active resolution and scaling tier.
- **Global Brightness Hotkeys, Fn-Mode Checker & Floating HUD**: Add global `☀️-` / `☀️+` media-key brightness control (default) plus opt-in literal `F1` / `F2` support (`1/16` steps, `1/64` fine steps with `⌥⇧`), defaulting **Target Display** routing to **Follow Mouse Cursor** (with options for **All Enabled Displays** and **Main Display**), displaying a brief auto-fading floating **Brightness HUD** on adjusted external displays, and surfacing a live macOS `Fn`-key mode and Accessibility permission checker inside a collapsible footer **Hotkeys** section.

## User Stories

1. As a macOS user, I want the **Brightness** slider to remain directly visible on every **Enabled Display** card, so that I can adjust monitor luminance immediately upon opening the popover.
2. As a macOS user, I want the legacy `Resolution` slider removed from **Enabled Display** cards, so that my card layout stays uncluttered and delegates mode picking to **Display Mode** and **Refresh Rate**.
3. As a macOS user, I want a collapsible **Display Mode** pill on each **Enabled Display** card showing my currently active resolution while collapsed, so that I can see each screen's resolution at a glance without expanding anything.
4. As a macOS user, I want a collapsible **Refresh Rate** pill on each **Enabled Display** card showing my currently active rate (such as `120Hz` or `24–120Hz`) while collapsed, so that I can verify frame-rate state at a glance.
5. As a macOS user, I want the `⌄` disclosure chevron at the bottom of each **Enabled Display** card preserved for **Set as Main Display**, so that transferring the **Main Display** remains simple and familiar.
6. As a macOS user, I want expanding **Display Mode**, **Refresh Rate**, **Set as Main Display**, or the footer **Hotkeys** section to automatically collapse any other expanded section across the popover, so that the popover stays compact and readable.
7. As a macOS user, I want the **Display Mode** list to live inside a height-capped scrollable container, so that monitors with over a thousand modes do not push the popover off the bottom of my screen.
8. As a macOS user, I want unsafe, stretched, and sub-720p modes automatically hidden from the **Display Mode** browser, so that I never accidentally pick an unreadable or distorted mode.
9. As a macOS user, I want a **Default and native modes** section pinned near the top of **Display Mode** showing the **Default Mode** (`★`) and **Native Mode** (`≡`), so that I can jump back to macOS's recommended or 1:1 panel mode immediately.
10. As a macOS user, I want every **Display Mode** row to display its logical resolution (`WidthxHeight`), an active checkmark when selected, and metadata badges for **HiDPI** (`✦`), aspect ratio (e.g. `16:9`), refresh rate (e.g. `120Hz`), and color depth (e.g. `10bit` or `8bit`), so that I know exactly what each mode configures before clicking it.
11. As a macOS user, I want clicking any **Display Mode** row to switch to that mode immediately without waiting for a separate apply button, so that switching feels instantaneous.
12. As a macOS user, I want a **`Filter...`** button inside **Display Mode** that expands interactive filter chips grouped by aspect ratio, refresh rate, color depth, and scaling (**HiDPI** / **LoDPI**), so that I can narrow down hundreds of modes cleanly.
13. As a macOS user, I want clicking a filter chip to select that option alone within its group while holding `⇧ Shift` and clicking lets me multi-select chips, so that I can combine e.g. `120Hz` + `60Hz` or `HiDPI` + `LoDPI` effortlessly.
14. As a macOS user, I want **`Show All`** and **`Reset Default`** action buttons inside the **`Filter...`** panel, so that I can inspect every safe mode on demand or return to sensible defaults in one click.
15. As a macOS user, I want an uncustomized **Display Mode** filter to track my display's native aspect ratio, active refresh rate, active color depth, and preferred **HiDPI**/**LoDPI** tier automatically—even after I change **Refresh Rate**—so that the default mode list stays relevant.
16. As a macOS user, I want any explicit **`Filter...`** chip selections I make to persist per physical display across refresh-rate switches and app restarts until I click **`Reset Default`**, so that my custom filter preferences are remembered.
17. As a macOS user, I want 5 per-display **Favorite Mode** slots (`1`–`5`) available free without any paywall or Pro upsell, so that I can bookmark my preferred setups on every monitor.
18. As a macOS user, I want a **`Manage...`** panel inside **Display Mode** showing slots `1`–`5` (with filled indicators for occupied slots) where I can assign the active **Display Mode** or clear an occupied slot, so that managing favorites is quick and visual.
19. As a macOS user, I want to right-click any **Display Mode** row to assign it to Favorite slot `1`–`5` or remove it from Favorites, so that I can organize favorites without activating each mode first.
20. As a macOS user, I want assigned **Favorite Modes** displayed in a **Favorites** section above **Default and native modes** for one-click switching, so that my top modes are always first in line.
21. As a macOS user, I want **Favorite Modes** persisted per physical display and matched by mode attributes if macOS reassigns `modeID` across reconnects, so that favorites remain reliable after unplugging or sleep.
22. As a macOS user, I want the **Refresh Rate** picker to show all refresh rates exposed by macOS for my current logical resolution and **HiDPI**/**LoDPI** tier, so that changing frame rate preserves my current screen scaling.
23. As a macOS user, I want **Variable Refresh Rate** modes (such as `48–120Hz (Variable)`) shown clearly at the top of **Refresh Rate** whenever macOS exposes **Variable Refresh Rate** for that display, so that I can enable or disable **Variable Refresh Rate** easily.
24. As a macOS user, I want **NTSC Refresh Rates** (such as `119.88Hz`, `59.94Hz`, `47.95Hz`, `29.97Hz`, `23.98Hz`) shown in a separated sub-section inside **Refresh Rate** whenever macOS exposes them for that display, without injecting unexposed timings that vanish on mode changes, so that video-cadence options stay truthful to the hardware.
25. As a macOS user, I want **Brightness Hotkeys** to bind macOS media keys (`☀️-` / `☀️+`) by default, so that standard Mac top-row keys (or `Fn+F1` / `Fn+F2` when flipped) control display brightness out of the box.
26. As a macOS user, I want an opt-in **"Bind literal F1 / F2"** toggle inside the footer **Hotkeys** section, so that when I use an external PC keyboard or flip macOS to standard function keys, pressing `F1` decreases brightness and pressing `F2` increases it directly without holding `Fn` (while keeping `F1`/`F2` free for other apps when disabled).
27. As a macOS user, I want **Brightness Hotkeys** to step brightness by `1/16` (`6.25%`) per press and finely by `1/64` (`1.56%`) when holding `⌥⇧`, including smooth key-repeat while held, so that stepping matches macOS's native tactile cadence.
28. As a macOS user, I want **Brightness Hotkeys** to default to **Follow Mouse Cursor** as the **Target Display** (adjusting whichever **Enabled Display** contains the pointer, falling back to the **Main Display**), so that whichever monitor I am actively working on responds immediately.
29. As a macOS user, I want a **Target Display** selector in the **Hotkeys** panel allowing me to switch between **Follow Mouse Cursor**, **All Enabled Displays**, and **Main Display**, so that I can synchronize all screens or lock keys to my **Main Display** when preferred.
30. As a macOS user, I want **All Enabled Displays** mode to step each **Enabled Display** relative to its own current brightness (`0%–100%` clamped), rather than snapping disparate monitors to the same percentage, so that balanced multi-monitor calibration is preserved.
31. As a macOS user, I want pressing `☀️-` / `☀️+` when the **Target Display** is solely the **Built-in Display** to pass through to macOS so Apple's native backlight and system OSD handle it cleanly, while pressing `☀️-` / `☀️+` when targeting an external display (or **All Enabled Displays**) suppresses the macOS event and routes brightness through OpenBetterDisplay's DDC/software-gamma pipeline, so that the **Built-in Display** does not dim unintentionally.
32. As a macOS user, I want a brief, auto-fading dark translucent **Brightness HUD** pill (display icon, name, bar, and `%`) shown on each external **Target Display** when adjusted by a **Brightness Hotkey**, so that I get clear visual feedback without stealing focus from active apps.
33. As a macOS user, I want a collapsible **Hotkeys** row in the popover footer (right above `Launch at Login`) containing a live **Keyboard & Permission Checker** that reports (a) whether macOS is currently set to top-row media keys or standard `F1`–`F12` (`Fn` required for `☀️`), with a button to open Keyboard Settings, and (b) whether Accessibility permission is granted, with an explicit **"Enable Accessibility…"** button, so that I always know why a hotkey behaves the way it does without being surprised by unsolicited permission popups at launch.
34. As a macOS user, I want **Disconnected Displays** ignored by **Brightness Hotkey** targeting (`Follow Mouse Cursor` and `All Enabled Displays`) and collapsed without **Display Mode** / **Refresh Rate** controls, so that disconnected monitors never disrupt hotkey behavior or clutter the popover.

## Implementation Decisions

### 1. Enriched Display Mode & Refresh Rate Model (`OpenBetterDisplayCore`)

- Extend raw mode representations and UI-facing mode options to carry all macOS-exposed attributes required by the **Display Mode** browser and **Refresh Rate** picker:
  - Color depth (`bitsPerSample`, distinguishing `10bit` vs `8bit` from SkyLight mode descriptions at `+0x1C` with `+0x30` fallback).
  - Mode classification flags: **Default Mode** (`kDisplayModeDefaultFlag`), **Native Mode** (`kDisplayModeNativeFlag`), hardware-safety/stretched flags, and sub-720p filtering (`height >= 720` and usable/safe for desktop).
  - Refresh rate range metadata: **Variable Refresh Rate** indicator and minimum/maximum Hz (e.g. `48–120Hz` / `24–120Hz`) alongside exact nominal refresh rate so integer rates and fractional **NTSC Refresh Rates** (`119.88Hz`, `59.94Hz`, `47.95Hz`, `29.97Hz`, `23.98Hz`) remain distinct and recognizable.
  - Display geometry/bounds on raw display descriptors (`CGDisplayBounds`) so pointer-in-display **Target Display** lookup works cleanly without leaking AppKit screen objects into Core state.
- Follow **ADR-0002**: expose only **Display Modes** and refresh rates returned by macOS (`CGDisplayCopyAllDisplayModes` and SkyLight mode descriptions); never fabricate synthetic custom scaled modes or unexposed NTSC timings.

### 2. Coordinator State, Filtering & Persistence (`OpenBetterDisplayCore`)

- **`DisplayCoordinator` remains the single observable state seam**:
  - Replace slider preview/commit mode tracking with immediate **Display Mode** selection and per-display **Refresh Rate** selection (`selectDisplayMode` / `selectRefreshRate` matching active logical resolution + scaling tier).
  - Maintain single-open accordion state across the entire popover (`expandedSection` enum covering per-display `displayMode`, `refreshRate`, `mainDisplay`, and footer `hotkeys`), clearing automatically on display disconnect, unplug, or popover close.
  - Manage per-display **Display Mode** custom filter state:
    - Derive available filter chip options dynamically from each display's safe `>= 720p` modes (aspect ratios, refresh rates including **Variable Refresh Rate** / **NTSC Refresh Rates**, bit depths, **HiDPI** / **LoDPI**).
    - When uncustomized, default filter tracks the display's native aspect ratio, active refresh rate, active bit depth, and preferred **HiDPI** / **LoDPI** tier.
    - When customized via chip selection (plain click = solo-select within group; `⇧ Shift`+click = multi-select) or `Show All`, persist the customized filter per physical display key until `Reset Default`.
  - Manage 5 **Favorite Mode** slots (`1`–`5`) per physical display key:
    - Store stable mode attributes (logical width/height, pixel width/height, refresh rate, bit depth, plus `modeID`) so favorites still match if `modeID` changes across reconnects/reboots.
    - Support assign-current, assign-specific-mode (via context menu), clear-slot, and one-click apply.
  - Coordinate **Brightness Hotkeys**:
    - Accept normalized hotkey events (`direction: decrease | increase`, `source: mediaBrightness | literalFunctionKey`, `isFine: Bool`, `pointerLocation: CGPoint?`).
    - Resolve **Target Display** list according to `HotkeyPreferences.targetMode` (`followMouseCursor` → **Enabled Display** whose bounds contain pointer, falling back to **Main Display**; `allEnabledDisplays` → all **Enabled Displays**; `mainDisplay` → **Main Display**).
    - Compute relative delta (`±1/16` = `±0.0625`, or `±1/64` = `±0.015625` when fine-stepping), apply independently per target via `setBrightness` (retaining DDC throttling and software-gamma fallback), and decide whether to consume (`true`) or pass through (`false` when a `☀️-`/`☀️+` media key resolves solely to the **Built-in Display**).
    - Emit HUD update payloads for adjusted external **Target Displays**.
- **Persistence**: Extend persistence abstractions cleanly (backed by `UserDefaults` in production and in-memory fakes in tests) for per-display **Favorite Modes**, per-display custom **Display Mode** filter configurations, and global **Brightness Hotkey** preferences.

### 3. System Input, Checker & Floating Brightness HUD (`OpenBetterDisplayCore` + `OpenBetterDisplay`)

- Follow **ADR-0001** with a single new OS boundary seam (`BrightnessHotkeyGateway`) isolating macOS input/checker/HUD APIs from coordinator routing:
  - **Media Brightness Keys (`☀️-` / `☀️+`)**: Active `CGEventTap` (`kCGEventTapOptionDefault`) monitoring `NX_SYSDEFINED` brightness-down/up key events when Accessibility is trusted (`AXIsProcessTrusted()`). On each key down/repeat, queries coordinator whether to consume (`nil`) or pass through (`event`) based on **Target Display** resolution.
  - **Opt-In Literal `F1` / `F2`**: Carbon `RegisterEventHotKey` (`kVK_F1` / `kVK_F2`, including `⌥⇧` fine-step modifier combos when enabled) functioning without Accessibility permissions whenever **"Bind literal F1 / F2"** is enabled, and unregistered cleanly when disabled or on app termination.
  - **Live Keyboard & Permission Checker**: Reads `IOHIDEventSystemClientCopyProperty(..., "HIDFKeyMode")` (with `CFPreferences` `com.apple.keyboard.fnState` fallback) and `AXIsProcessTrusted()`, refreshing whenever the popover opens or `Hotkeys` expands. Never auto-prompts Accessibility on startup; provides explicit **"Enable Accessibility…"** (triggering `AXIsProcessTrustedWithOptions` prompt / System Settings deep link) and **"Open Keyboard Settings…"** actions.
  - **Floating Brightness HUD (`OpenBetterDisplayUI` / `OpenBetterDisplay`)**: Non-activating, click-through `NSPanel` per adjusted external **Target Display** displaying a dark translucent HUD pill (monitor symbol, display name, smooth brightness bar, percentage) positioned near the bottom-center of that display and auto-fading after ~1.2 seconds (extending timer on repeated presses).

### 4. Popover SwiftUI Views (`OpenBetterDisplayUI`)

- Update display card layout: `headerPill` → `BrightnessControlRow` → `DisplayModeSection` (collapsed pill + expanded scrollable panel with `Favorites` + `Manage...`, `Default and native modes`, `Modes matching custom filter` + `Filter...` chips) → `RefreshRateSection` (collapsed pill + expanded list with **Variable Refresh Rate**, integer, and exposed **NTSC Refresh Rate** sub-section) → bottom `⌄` chevron for `MainDisplayDrawerRow`.
- Add footer collapsible `HotkeysSection` above `Launch at Login` containing **Target Display** picker, **Brightness Media Keys** / **Bind literal F1 / F2** toggles, and the live **Fn-Key Mode** + **Accessibility Permission** checker.
- Remove `ResolutionControlRow` and `SteppedResolutionSlider`. Update `PopoverPreview` fixtures/options to cover expanded **Display Mode** (with filter/manage subviews), **Refresh Rate**, and **Hotkeys** panels for visual regression inspection.

## Testing Decisions

- **Testing Philosophy**: Tests verify observable behavior and invariants across high-level boundaries (`DisplayCoordinator`, `DisplayModeFilter`, and binary/mode parsers), never private internal helpers or UI layout internals.
- **Modules Under Test**:
  - `OpenBetterDisplayCore` (`DisplayCoordinator`, `DisplayModeFilter`, mode metadata parsing, and hotkey routing/stepping/checker coordination).
- **Seams**:
  1. **Existing primary seam (`DisplayDriver`) + persistence/scheduler fakes**: Exercises all **Display Mode** filtering (`>= 720p`, unsafe/stretched exclusion, aspect/Hz/bit-depth/`HiDPI`/`LoDPI` chips, `⇧ Shift` multi-select, `Show All`, `Reset Default`, sticky custom filter vs dynamic default), **Favorite Modes** (`1`–`5` per physical display, fallback matching across `modeID` shifts), **Refresh Rate** switching (VRR, integer, exposed NTSC), and single-open accordion invariants using `FakeDisplayDriver` and in-memory stores.
  2. **Single new OS input/HUD seam (`BrightnessHotkeyGateway`)**: Isolates `CGEventTap`, Carbon `RegisterEventHotKey`, `IOHIDEventSystemClient` `HIDFKeyMode`, `AXIsProcessTrusted`, pointer coordinates, and floating `BrightnessHUD` presentation behind one fakeable gateway seam so tests deterministically verify cursor-under-display targeting, **All Enabled Displays** relative stepping, **Main Display** targeting, `☀️-`/`☀️+` **Built-in Display** passthrough vs external consumption, literal `F1`/`F2` toggling, `1/16` vs `⌥⇧` `1/64` steps, **Disconnected Display** exclusion, and HUD update emissions.
- **Prior Art**: Follows the existing behavioral test suite structure (`DisplayCoordinatorTests` using `FakeDisplayDriver`, `InMemoryBrightnessStore`, and `ManualBrightnessWriteScheduler`; `SkyLightDisplayModeTests` testing raw binary `SkyLightDisplayModeDescription` layouts).

## Out of Scope

- `Tools` menu (`Displays And Virtual Screens`, `Video Filter Window`, `System Colors`, `Check for Updates`), top toolbar icon bar, and `Get BetterDisplay Pro` / commercial licensing UI.
- Synthetic `"Show Custom Scaled Resolutions"` creation, virtual displays (`CGVirtualDisplay`), and EDID overrides.
- Unexposed **NTSC Refresh Rate** timing injection, `Configuration Protection` mode-enforcement daemons, and `⌥ Option`-hold live refresh rate measurement.
- Arbitrary custom global shortcut recorder beyond `☀️-`/`☀️+` media **Brightness Hotkeys** and opt-in `F1`/`F2` (`+ ⌥⇧` fine step).

## Further Notes

- Canonical terminology in this specification matches `GLOSSARY.md` (**Main Display**, **Main Display Badge**, **Enabled Display**, **Disconnected Display**, **Display Mode**, **HiDPI**, **LoDPI**, **Default Mode**, **Native Mode**, **Favorite Mode**, **Variable Refresh Rate**, **NTSC Refresh Rate**, **Brightness Hotkey**, **Target Display**).
- Design trade-offs are documented in **ADR-0001** (Hybrid Brightness Hotkey Capture and Fn-Mode Checker) and **ADR-0002** (macOS-Exposed Display Modes Only).
- `CGDisplayModeCopyPixelEncoding` (`CoreGraphics`) is a hardcoded 8-bit stub on macOS 26 (see `docs/macos-private-apis.md`), so bit depth is parsed from SkyLight mode descriptions (`+0x1C` with `+0x30` fallback).
- When building locally via `make app` with ad-hoc code signing, macOS TCC invalidates prior Accessibility trust on binary changes until re-granted in System Settings or signed with a stable developer certificate; the live Accessibility checker in the footer **Hotkeys** section makes this state immediately visible.
- All SwiftUI popover updates should be verified via `make preview` and visual inspection alongside `make check`.
