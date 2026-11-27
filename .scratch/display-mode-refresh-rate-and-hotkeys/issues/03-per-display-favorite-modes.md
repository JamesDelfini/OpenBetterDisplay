# 03: Per-Display 5-Slot Favorite Modes (Manage & Context Menu)

**What to build:** Add 5 free per-display **Favorite Mode** slots (`1`–`5`) inside **Display Mode** so users can bookmark and recall their preferred configurations with one click and zero paywall gating. Clicking **`Manage...`** reveals numbered slots `1`–`5` (with filled indicators for occupied slots) to assign the currently active **Display Mode** or clear an occupied slot, right-clicking any **Display Mode** row offers **`Assign to Favorite 1…5`** / **`Remove from Favorites`**, and occupied slots render in a **`Favorites:`** section at the top of **Display Mode**—persisting per physical display and falling back cleanly to matching mode attributes if macOS reassigns `modeID` across reconnects.

**Blocked by:** 01: Card Layout Transition & Core Display Mode Browser

**Status:** resolved

- [x] **Display Mode** includes a **`Manage...`** toggle at the top showing slots `1`–`5` with distinct empty vs filled indicators for the display's **Favorite Modes** (with no `Pro` badge or gating).
- [x] Clicking an empty slot in **`Manage...`** assigns the display's currently active **Display Mode** to that slot; clicking an occupied slot (or clearing via action) updates or clears that slot cleanly.
- [x] Right-clicking any **Display Mode** row presents a context menu to assign that row's mode to Favorite slot `1`–`5` or remove it if already favorited.
- [x] Whenever one or more **Favorite Modes** are assigned for a display, a **`Favorites:`** section renders above **Default and native modes** with one-click switching; when none are assigned, the empty-state prompt appears as in the reference UI.
- [x] **Favorite Modes** persist per physical display across restarts and still resolve to the matching **Display Mode** via logical resolution, pixel dimensions, refresh rate, and color depth if macOS reassigns `modeID` after reconnect or reboot.
- [x] Behavioral tests across `DisplayDriver` and an in-memory persistence store verify per-display 5-slot assignment, clearing, replacement, one-click switching, and `modeID`-shift fallback resolution; UI preview rendering and `make check` pass cleanly.

## Comments

- Implemented on `ticket-03-per-display-favorite-modes` (`0202f77`), merged into `feat/display-mode-refresh-rate-and-hotkeys` in `3943bcc`, and refined after two-axis code review in `f708002` / `0d028e2` (added `isVariableRefreshRate` / `minRefreshRate` matching on `modeID` shifts, `fallbackModeOption`, shared `UserDefaultsJSONStore`, and serial-less physical persistence keys).
