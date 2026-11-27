# macOS Private APIs & AppKit Invariants

Verified on Apple Silicon (M4 Pro, `arm64`, macOS 26.7.3). All private symbols load dynamically via `DynamicLibrary` (`dlopen`/`dlsym`) so builds require only public SDK headers.

## IOKit (`IOAVService*` — Apple Silicon DDC/CI)

- **Defining library:** `/System/Library/Frameworks/IOKit.framework/IOKit` (not `IOMobileFramebuffer`).
- **Symbols:** `IOAVServiceCreateWithService`, `IOAVServiceReadI2C`, `IOAVServiceWriteI2C`, `IOAVServiceCopyEDID`, `IOAVServiceGetLocation`.
- **Memory & bounds:** `IOAVServiceCreateWithService` and `IOAVServiceCopyEDID` return `+1` retained CF objects (`takeRetainedValue()`). I2C read/write buffers must be `<= 4096` bytes.
- **M4 IORegistry topology:** `AppleCLCD2` does not exist on M4 (`IOMobileFramebufferShim` sits under `disp0@0`/`dispext0@...`), `DCPAVServiceProxy` lives under sibling `dcp*` EPIC paths, and the built-in eDP panel also creates a `DCPAVServiceProxy` with `Location == "Embedded"` (`IOAVServiceGetLocation == 1`). Always enumerate `IOServiceMatching("DCPAVServiceProxy")` directly, exclude `"Embedded"`, and match candidates via `IOAVServiceCopyEDID` (vendor/model/serial/name) with `IODisplayLocation` pipe token (`dispextN`) as tie-breaker.
- **DDC/CI VCP `0x10` (Luminance):**
  - Chip address `0x37` (`0x6E` on wire); write `dataAddress = 0x51`; read `dataAddress = 0x00`.
  - Write packet (6 bytes): `[0x84, 0x03, 0x10, valHi, valLo, chk]` (`chk = 0x6E ^ 0x51 ^ p[0...4]`), sent in 2 cycles with `10ms` spacing.
  - Read request (4 bytes): `[0x82, 0x01, 0x10, 0xAC]`, wait `40–50ms`, read 11-byte reply verifying `0x50 ^ r[0...9] == r[10]`, `r[2] == 0x02`, `r[3] == 0x00`, `r[4] == 0x10`, `max = r[6]<<8 | r[7]`, `cur = r[8]<<8 | r[9]`.
- **Sandbox note:** Seatbelt-sandboxed CLI processes receive `nil` from `IOAVServiceCreateWithService`; unsandboxed ad-hoc signed `OpenBetterDisplay.app` operates normally.

## DisplayServices (Built-in Backlight)

- **Library:** `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices`
- **Symbols:** `DisplayServicesCanChangeBrightness`, `DisplayServicesGetBrightness`, `DisplayServicesSetBrightness` (`Int32` status: `0` = success, `1000` = failure). Always gate built-in brightness calls with `DisplayServicesCanChangeBrightness` so external monitors fall through cleanly to DDC/CI or software gamma.

## SkyLight (Display Power & Modes)

- **Library:** `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`
- **Symbols:** `CGSGetDisplayList`, `CGSConfigureDisplayEnabled`, `CGSGetNumberOfDisplayModes`, `CGSGetDisplayModeDescriptionOfLength`, `CGSGetCurrentDisplayMode`, `CGSConfigureDisplayMode`.
- **Mode description layout (`SkyLightDisplayModeDescription`):** 212-byte little-endian struct (`0x00` modeNumber, `0x04` flags, `0x08` width, `0x0C` height, `0x10` depth [reports `8` even on 10-bit modes], `0x1C` `UInt32` `bitsPerSample`, `0x24` intFreq, `0x30` `char[128]` null-terminated ASCII pixel encoding fallback e.g. `"--RRRRRRRRRRGGGGGGGGGGBBBBBBBBBB"`, `0xBC` fixed-point 16.16 refresh rate, `0xC0` ioFlags, `0xC4` ioDisplayModeID, `0xC8` pixelWidth, `0xCC` pixelHeight, `0xD0` Float scale).
- **Flags & pixel encoding caveats:**
  - `kDisplayModeDefaultFlag` (`0x0000_0004`) marks the factory **Default Mode** (`★`); `kDisplayModeStretchedFlag` (`0x0000_0800`) and `0x4000_0000` mark stretched/unsafe modes excluded from the **Display Mode** browser.
  - `kDisplayModeNativeFlag` (`0x0200_0000`) is set on **both** 1x physical-grid modes and their 2x HiDPI pixel-doubled counterparts; identifying the 1:1 **Native Mode** (`≡`) requires `isNative && width == pixelWidth && height == pixelHeight`.
  - `CGDisplayModeCopyPixelEncoding` (`CoreGraphics`) is a hardcoded stub on macOS 26 returning 8-bit `"--------RRRRRRRRGGGGGGGGBBBBBBBB"` for all modes; read `bitsPerSample` from SkyLight `+0x1C` (with `+0x30` fallback) and preserve it when merging SkyLight metadata onto `CGDisplayMode` entries.

## CoreDisplay & EDID Name Fallback

- Resolve external names in order: `CoreDisplay_DisplayCreateInfoDictionary` (`DisplayProductName`) → `NSScreen.screens` (`localizedName`) → IOKit `IODisplayConnect` / `IOAVServiceCopyEDID` descriptor tag `0xFC` → `"External Display (%04X:%04X)"`.

## AppKit `NSPopover` & Display Reconfiguration

- Calling `popover.performClose(nil)` while `popover.animates = true` leaves `popover.isShown == true` during fade-out. When transferring the **Main Display**, `CGConfigureDisplayOrigin` relocates the macOS menu bar immediately, glitching any open or fading popover.
- Dismiss `NSPopover` synchronously (`animates = false; popover.close(); animates = previous`) **before** invoking `driver.setMainDisplay(_:)` so `isShown == false` and `popoverDidClose` completes before `CGCompleteDisplayConfiguration`.
