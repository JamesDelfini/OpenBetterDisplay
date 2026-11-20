## Agent skills

### Issue tracker

Issues and specs live as local markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the default five canonical triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (`GLOSSARY.md` and `docs/adr/` at the repo root). See `docs/agents/domain.md`.

### Build, checks & UI preview

Run `make check`, `make test-quiet`, `make build`, `make app`, or `make preview` (never bare `swift` commands) so sandboxed module caches isolate automatically per worktree. After SwiftUI popover edits, run `make preview` and inspect `/tmp/openbetterdisplay-preview.png`.

### macOS private APIs

Before editing `MacOSDisplayDriver`, `AppleSiliconDDCClient`, SkyLight/IOKit/DisplayServices symbols, or `NSPopover` display-reconfiguration hooks, read `docs/macos-private-apis.md`.
