import { mkdirSync, writeFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { Plugin } from "@opencode/plugin/tui"

/**
 * NotchGlow TUI side for OpenCode v1: the server plugin runs in the
 * background service and never sees TUI quit. This TUI plugin writes CLEAR
 * when the TUI exits and unloads its plugins.
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
