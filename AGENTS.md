# AGENTS.md

Guidance for AI agents (Claude Code, opencode, etc.) working in this repository.

## What this is

**NotchGlow** — a native macOS menu-bar app that draws a colored rounded rectangle around the MacBook notch. A watched file's content (e.g. `RED`, `GREEN`) drives the color. Primary use case: Claude Code / opencode hooks signal agent state visually (waiting → red, working → yellow, done → green).

## Repo layout

```
Sources/main.swift   — entire app (~250 lines, single file, no dependencies)
Sources/render-icon.swift — standalone script that renders the 1024px app icon PNG
plugins/notchglow/   — OpenCode V2 plugin (server: `index.ts`, TUI exit hook: `tui.ts`, needs `npm install` for @opencode/plugin)
Info.plist           — app bundle manifest (LSUIElement: no dock icon)
Makefile             — builds build/NotchGlow.app with swiftc, no Xcode project
README.md            — user-facing docs
build/               — build output, gitignored-worthy
```

## Build & test

```sh
make                    # builds build/NotchGlow.app (requires Xcode CLT / swiftc)
make run                # runs with defaults: --file ~/.notch-color --interval 10
make install            # copies bundle to /Applications
make clean
```

Manual run without bundle (useful for debugging — logs to stderr):

```sh
swiftc -O -target arm64-apple-macosx12.0 Sources/main.swift -o /tmp/ng
echo GREEN > ~/.notch-color
/tmp/ng --file ~/.notch-color --interval 5
```

There is no test suite. Verification workflow used so far:

1. Window check — confirm overlay window exists and is highest layer:
   `CGWindowListCopyWindowInfo([.optionOnScreenOnly], ...)`, filter `kCGWindowLayer > 25`.
2. Geometry check — print `NSScreen.auxiliaryTopLeftArea/Right` + `safeAreaInsets`; notch rect = `(left.maxX, frame.maxY - safeAreaInsets.top, right.minX - left.maxX, safeAreaInsets.top)`.
3. Pixel check — render border into `NSBitmapImageRep` offscreen and sample `colorAt(x:y:)`; remember bitmap origin is top-left, AppKit screen coords are bottom-left (flip y: `bitmapY = screenHeight - appkitY`).
4. `screencapture` usually fails from agent terminals (no Screen Recording permission) — don't rely on screenshots.

## Architecture notes

- Single overlay `NSWindow` covering the full screen frame (borderless, transparent, `ignoresMouseEvents`, level = `.maximumWindow`, `canJoinAllSpaces`). Full-screen window avoids repositioning logic; the view just draws the border at the notch rect.
- Notch detection: screen where `safeAreaInsets.top > 0`. Handles 14"/16" automatically. If no notch found, falls back to a **fake notch** (`fakeNotchRect(for:)`): top-center pill on the first non-builtin screen (detected via `CGDisplayIsBuiltin` on `NSScreenNumber`), width = screen/9.6 clamped 160…300pt, height = width × 0.17. The fake notch is drawn as a solid color fill (bottom corners rounded only, top flush with screen edge via `roundedPath(_:radius:bottomOnly:)`) plus a soft halo — the real-notch border style strokes, the fake one fills. If no screen at all is found, window hides.
- Border is inset by −2.5pt around the notch rect with lineWidth 5, plus a softer outer glow pass at −5.5pt. Top edge of the border lands above the screen top (notch touches screen edge), so only left/right/bottom sides are visible — that is intentional, not a bug.
- Polling: `Timer` reads the file, compares raw content to skip redundant redraws. Unrecognized non-empty content logs to stderr and keeps the current state; `CLEAR`/`NONE`/`OFF`/empty hides the border.
- Colors: named (`RED/GREEN/YELLOW/ORANGE/BLUE/PURPLE`, case-insensitive) or `#RRGGBB`. Add new names in `parseColor(_:)`.
- Config: CLI args `--file` / `--interval` (`Config.fromArgs`). Interval also changeable live from the menu. Persisted preferences do not exist.
- Blinking: while a color is set, the overlay toggles hidden/visible every 0.6s (`blinkTimer` in `AppDelegate`, `OverlayWindowController.setBlink(hidden:)`). Default off; toggle via the "Blinking" menu item. When off or no color set, the blink phase resets to visible.
- App icon: `render-icon.swift` generates `build/icon-1024.png`; Makefile turns it into `AppIcon.icns` via `sips`+`iconutil` and bundles it (`CFBundleIconFile` in Info.plist). Edit the Swift script, then `rm build/icon-1024.png && make` to regenerate.
- Repositioning on display changes via `NSApplication.didChangeScreenParametersNotification`.

## Gotchas

- **macOS 12+ APIs only** (`auxiliaryTopLeftArea`, `safeAreaInsets`) — build target is pinned to `arm64-apple-macosx12.0` in the Makefile.
- `NSMenuItem(title:action:keyEquivalent:)` has **no `target:` parameter** — set `item.target = self` separately.
- Screen-coordinate vs view-coordinate conversion lives in `OverlayWindowController.update()` — notch rects are global screen coords, the view draws in window coords, so rects are translated by `−screen.frame.origin` (matters for external screens at nonzero origins). The view assumes the window frame exactly equals the screen frame. Keep those invariants if you change window setup.
- Swift 6 toolchain — keep code clean of strict-concurrency warnings if adding actors/async.

## Roadmap (not yet done)

- Claude Code hooks that write `RED`/`YELLOW`/`GREEN`/`CLEAR` to the watched file (the OpenCode side is done: `plugins/notchglow/`, installed globally to `~/.config/opencode/plugins/notchglow/`).
- Possible additions: custom colors via CLI flags, per-display overlays, login-item packaging.

## OpenCode plugins

### V2 plugin (`plugins/notchglow/`)

V2 plugin (`Plugin.define`, `@opencode/plugin`) subscribing to the server event stream and writing the color file. Companion TUI plugin `tui.ts` (`@opencode/plugin/tui`, exposed via the `./tui` export in package.json) writes `CLEAR` when the TUI exits — the server plugin runs in the background service, which outlives the TUI, so it never sees the quit. Gotchas:

- **Discovery**: a root-level `plugins/` dir is NOT auto-discovered — only `.opencode/plugins/` per project or `~/.config/opencode/plugins/` globally. The global copy is the live one; this repo is the source of truth. Reinstall after edits: `npm install --prefix plugins/notchglow && cp -r plugins/notchglow ~/.config/opencode/plugins/ && opencode api post /api/location/reload --data '{}'`.
- `@opencode/plugin` must resolve from the plugin directory (node_modules), otherwise load fails with `Cannot find package '@opencode/plugin'`.
- Event payloads carry the session id at `event.data.sessionID`, not `event.sessionID`. Real lifecycle events: `session.execution.started|succeeded|failed|interrupted`, `permission.asked|replied`.
- Debug loads: `grep notchglow ~/.local/share/opencode/log/opencode.log`, check state via `opencode api get /api/plugin`.

### V1 plugin (`plugins/notchglow-v1/notchglow.ts`)

Single dependency-free file for OpenCode v1 (tested on 1.18.x). Plain plugin function (no `Plugin.define`, no `@opencode-ai/plugin` import — the type import is commented out so it loads without node_modules). Install: `cp plugins/notchglow-v1/notchglow.ts ~/.config/opencode/plugins/notchglow.ts` — v1 auto-discovers `*.{ts,js}` one level deep in `plugin(s)/` under each config dir (`~/.config/opencode`, project `.opencode/`).

Differences from V2:

- V1 has no `session.execution.*` events. Mapping: busy ← `session.status` (`status.type: "busy"|"retry"`), done ← `session.idle`, failed/interrupted ← `session.error` (covers abort via `MessageAbortedError`), permission asked ← `permission.updated` (v1.18; some versions may use `permission.asked` — check the SDK `Event` union if RED never fires).
- Events arrive via an `event` hook `{ event: { type, properties } }` pushed to every hook; session id lives at `event.properties.sessionID`.
- No companion TUI plugin needed: v1 has a `dispose` hook that fires when the server instance shuts down, and the plugin writes `CLEAR` there (verified working after `opencode run` exits).
- Options (custom file path) not wired — edit `DEFAULT_FILE` in the file. V1 passes `options` as second arg to the plugin function (`Plugin = (input, options?) => Promise<Hooks>`) if ever needed.
- Verification without the app: run `opencode run "..."` while polling `~/.notch-color`; transitions seen live: CLEAR → YELLOW (busy) → GREEN (idle) → CLEAR (dispose). Headless `opencode run` auto-rejects permissions instantly, so RED is hard to catch there — simulate `permission.updated`/`permission.replied` directly to unit-test the RED path.
