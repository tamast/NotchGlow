# NotchGlow

Menu-bar app that draws a colored rounded rectangle around the MacBook notch, driven by a color read from a watched file. Works on any MacBook with a notch (14", 16") — geometry is detected at runtime via `NSScreen.auxiliaryTopLeftArea` / `safeAreaInsets`.

## Clamshell / external monitors

With the lid closed or on a screen without a notch, NotchGlow falls back to a fake notch: a solid color-filled pill hanging from the top-center edge of the external display (bottom corners rounded, sized like a real notch). Real notch always wins when present.

## Colors

File content (case-insensitive, whitespace ignored):

| Content | Border |
|---|---|
| `RED` | red |
| `GREEN` | green |
| `YELLOW` | yellow |
| `ORANGE`, `BLUE`, `PURPLE` | those |
| `#RRGGBB` | any hex color |
| `CLEAR` / `NONE` / `OFF` / empty | hidden |

Unrecognized content is logged to stderr and the current state is kept.

## Build & run

```sh
make            # builds build/NotchGlow.app
make run        # opens it with defaults
open build/NotchGlow.app --args --file ~/.notch-color --interval 5
```

Defaults: `--file ~/.notch-color --interval 10` (seconds). Interval can also be changed from the menu bar icon (1s/5s/10s/30s/60s) without restarting.

Install system-wide:

```sh
make install    # copies to /Applications
```

Launch at login: add `NotchGlow.app` to System Settings → General → Login Items (pass startup args via Login Items arguments if you need a custom file path).

## OpenCode / agent hooks

This repo ships an OpenCode V2 plugin at `plugins/notchglow/index.ts` that subscribes to the server event stream and writes the watched file:

- `YELLOW` — an agent turn is running (working)
- `RED` — a permission is waiting for your approval
- `GREEN` — the last turn finished successfully
- `CLEAR` — the turn failed or was interrupted (glow hidden)

The plugin also ships a companion TUI plugin (`plugins/notchglow/tui.ts`, auto-loaded via the `./tui` package export) that writes `CLEAR` when you quit OpenCode — the server plugin itself runs in the long-lived background service and never sees the TUI exit.

With multiple sessions running in parallel, the most recent signal wins.

### Install globally (all projects)

Install its dependency, then copy it into OpenCode's auto-discovered global plugins directory:

```sh
npm install --prefix plugins/notchglow   # provides @opencode/plugin (required at load time)
mkdir -p ~/.config/opencode/plugins
cp -r plugins/notchglow ~/.config/opencode/plugins/
opencode api post /api/location/reload --data '{}'   # or restart opencode
```

Every project now gets the hook — no per-project config needed. To uninstall: remove `~/.config/opencode/plugins/notchglow/`.

The watched file defaults to `~/.notch-color`; override it via plugin options in `~/.config/opencode/opencode.json(c)`:

```jsonc
{
  "plugins": [{ "package": "~/.config/opencode/plugins/notchglow", "options": { "file": "/tmp/notch-color" } }]
}
```

Note: `plugins/notchglow/` in this repo is only the source of truth. It sits outside `.opencode/plugins/`, so OpenCode does *not* auto-load it per-repo — the global copy is the one that runs (this avoids duplicate-ID conflicts if both load).

## Claude Code usage (planned)

Hooks will set the file content:

- `RED` — waiting for confirmation / input
- `YELLOW` — working
- `GREEN` — task finished
- `CLEAR` — hide

Hook setup is a separate task.
