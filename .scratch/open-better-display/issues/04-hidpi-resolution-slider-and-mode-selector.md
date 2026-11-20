# 04: HiDPI Resolution Slider & Clickable Mode Selector

**What to build:** A `Resolution` slider with a resize icon and `<Width>x<Height>` (or `<Width>x<Height> · <Scale>%` on HiDPI displays, such as `2560x1440 · 133%`) readout inside every active display card (hidden when the display is toggled OFF). The slider steps through clean display modes matching the display's native aspect ratio and current refresh rate, preferring crisp HiDPI modes on 4K/Retina displays. Dragging the slider previews the target resolution and scale percentage live without flickering the monitor, and releasing the slider commits the display mode switch. Clicking the resolution label opens a dropdown menu to jump directly to any available resolution stop.

**Blocked by:** 01: Tracer Bullet — Menu Bar App & Live Display Listing

**Status:** resolved

- [x] Every enabled display card shows a `Resolution` row with the current `<Width>x<Height>` (plus `· <Scale>%` on HiDPI displays) and a stepped horizontal slider with a resolution icon; turning the display OFF hides the Resolution control.
- [x] Available display modes for each monitor are filtered to the display's native aspect ratio and current refresh rate, preferring HiDPI modes on Retina/4K panels and standard native modes on 1x panels, sorted from lowest to highest resolution.
- [x] Dragging the Resolution slider updates the displayed `<Width>x<Height> · <Scale>%` label live during the drag without triggering intermediate mode switches.
- [x] Releasing the Resolution slider commits the selected display mode to macOS once.
- [x] Clicking the `<Width>x<Height> · <Scale>%` resolution text opens a dropdown list of the filtered resolution stops for that display and switches immediately when an item is selected.
- [x] Behavioral tests across the `DisplayDriver` seam verify native-aspect-ratio and refresh-rate filtering, HiDPI preference on 4K/Retina displays, scale percentage formatting (`2560x1440 · 133%` vs. `1920x1080`), live preview during slider drag without mode-switch calls, and single mode commit on slider release or dropdown selection.

## Comments

- Implemented on `ticket-04-resolution-slider` (`8926367`, `4448ba0`, `6c46195`), merged onto `feat/open-better-display` in `6872881`, and refined after code review in `af76b79` (SkyLight mode enumeration queries and accurate handling of filtered-out active modes).
