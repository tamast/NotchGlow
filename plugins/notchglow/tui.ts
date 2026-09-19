import { mkdirSync, writeFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { Plugin } from "@opencode/plugin/tui"

/**
 * NotchGlow TUI side: the server plugin (index.ts) runs in the background
 * service, which outlives the terminal UI, so it never sees "opencode quit".
 * This CLI plugin runs inside the TUI process and writes CLEAR when the TUI
 * exits and unloads its plugins.
 *
 * Auto-loaded via the "./tui" export beside the main plugin entry.
 *
 * Note: with several TUIs running in parallel, quitting any one of them
 * clears the shared color file (same "most recent signal wins" spirit as
 * the server side).
 */

const DEFAULT_FILE = resolve(process.env.HOME ?? ".", ".notch-color")

export default Plugin.define({
  id: "notchglow.tui",
  setup(ctx) {
    const options = (ctx.options ?? {}) as { file?: string }
    const file = options.file ? resolve(options.file) : DEFAULT_FILE

    return () => {
      try {
        mkdirSync(dirname(file), { recursive: true })
        writeFileSync(file, "CLEAR\n", "utf8")
      } catch (error) {
        console.error(`notchglow: failed to clear ${file}:`, error)
      }
    }
  },
})
