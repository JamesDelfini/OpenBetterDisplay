# Coding Standards

Judgement calls enforced during `/code-review`. Mechanical checks (compiler warnings, `swift format`, test-double placement, leftover debug tags) live in `make check` and are omitted here.

## Truthful UI & Recoverable Hardware Fallbacks

- Re-read real OS state after errors rather than faking optimistic UI state in `catch` blocks (e.g., `Launch at Login` must re-read `SMAppService.mainApp.status`).
- Treat transient hardware failures (such as a DDC/CI timeout while a monitor wakes from standby) with bounded cooldowns rather than permanently caching `.unsupported`. Allow DDC writes with default `maxValue = 100` when a valid `IOAVService` exists even if an initial read timed out; fall back to software gamma only when the write fails.
- Preserve the real OS `currentModeID` and resolution label when the active mode falls outside filtered slider stops so selecting a filtered stop still commits instead of no-oping.

## Popover Lifecycle Across Display Reconfiguration

- Close `NSPopover` synchronously (`animates = false; popover.close()`) before any CoreGraphics or SkyLight call that relocates screen origins or the macOS menu bar (such as `setMainDisplay`).

## Domain Vocabulary

- Match canonical terms in [GLOSSARY.md](./GLOSSARY.md) across symbols, comments, tests, and specs (**Main Display**, **Main Display Badge**, **Enabled Display**, **Disconnected Display**). Replace avoided synonyms (`isActive` when meaning `isMain`, `M icon`, `active display`).

## Module Shape & Boundaries

- Keep `DisplayCoordinator` as the single observable state seam across `DisplayDriver`, and split standalone pure logic (mode filtering, DDC protocol parsing, name formatting) into focused files rather than growing God classes.
- Bundle per-display coordination fields into a single value struct instead of parallel `[UInt32: ...]` dictionaries.
- Share reusable HUD controls (such as `HUDSlider`) across rows instead of duplicating geometry and gesture math.
