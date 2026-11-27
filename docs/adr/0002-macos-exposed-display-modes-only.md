# macOS-Exposed Display Modes Only (No Synthetic EDID Timings)

Status: accepted

OpenBetterDisplay exposes every safe, `>= 720p` **Display Mode** and refresh rate reported natively by macOS (`CGDisplayCopyAllDisplayModes` and SkyLight `CGSGetDisplayModeDescriptionOfLength`), including **Variable Refresh Rate** modes and hardware-advertised **NTSC Refresh Rates**, while deliberately excluding synthetic custom scaled resolutions, unexposed timing injection, and `Configuration Protection` enforcement.

## Considered Options

- **Inject custom EDID overrides / unexposed NTSC timings + Configuration Protection**: Can fabricate fractional rates (such as `59.94Hz` or `119.88Hz`) or arbitrary scaled resolutions even when a monitor/cable link does not advertise them, but requires persistent WindowServer overrides, reset recovery, and ongoing fighting against macOS mode changes.
- **macOS-exposed Display Modes and refresh rates only (chosen)**: Relies directly on the mode list macOS WindowServer already makes available (which on modern Apple Silicon already includes fine-grained 32 px-stepped **HiDPI** modes, `10bit` pixel encodings, **Variable Refresh Rate**, and display-advertised **NTSC Refresh Rates**), keeping mode switching transactional, deterministic, and bloat-free.

## Consequences

- **NTSC Refresh Rates** appear in the **Refresh Rate** section only on displays/connections where macOS exposes fractional rates (such as `59.94Hz` / `47.95Hz` on the **Built-in Display**); displays that do not expose them omit the NTSC section instead of showing warnings about persistence.
- Custom `"Show Custom Scaled Resolutions"` creation and `Configuration Protection` background daemons remain out of scope.
