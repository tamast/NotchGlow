# NotchGlow

Menu-bar app that draws a colored rounded rectangle around the MacBook notch, driven by a color read from a watched file. Works on any MacBook with a notch (14", 16") — geometry is detected at runtime via `NSScreen.auxiliaryTopLeftArea` / `safeAreaInsets`.

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

## Claude Code usage (planned)

Hooks will set the file content:

- `RED` — waiting for confirmation / input
- `YELLOW` — working
- `GREEN` — task finished
- `CLEAR` — hide

Hook setup is a separate task.
