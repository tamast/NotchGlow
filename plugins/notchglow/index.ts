import { mkdir, readFile, writeFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { Plugin } from "@opencode/plugin"

/**
 * NotchGlow hook: mirrors OpenCode agent state into the color file watched by
 * the NotchGlow menu-bar app.
 *
 *   YELLOW — an agent turn is running (working)
 *   RED    — a permission is waiting for user approval
 *   GREEN  — the last turn finished successfully
 *   CLEAR  — the turn failed or was interrupted (hide the glow)
 *
 * Companion CLI plugin: tui.ts (loaded via the "./tui" export) writes CLEAR
 * when the OpenCode TUI exits, because this server plugin runs in the
 * long-lived background service and never sees the TUI quit.
 *
 * Install globally by copying this directory to
 * ~/.config/opencode/plugins/notchglow/ (auto-discovered in every project).
 * The directory must contain its node_modules (run `npm install` here first):
 * @opencode/plugin has to resolve for the plugin to load.
 *
 * The watched file defaults to ~/.notch-color and can be overridden with the
 * "file" plugin option:
 *
 *   "plugins": [{ "package": "~/.config/opencode/plugins/notchglow", "options": { "file": "/tmp/notch-color" } }]
 *
 * When several sessions run in parallel, the most recent signal wins.
 */

const DEFAULT_FILE = resolve(process.env.HOME ?? ".", ".notch-color")

const COLOR = {
  yellow: "YELLOW\n",
  red: "RED\n",
  green: "GREEN\n",
  clear: "CLEAR\n",
} as const

async function writeColor(file: string, color: string): Promise<void> {
  try {
    await mkdir(dirname(file), { recursive: true })
    await writeFile(file, color, "utf8")
  } catch (error) {
    console.error(`notchglow: failed to write ${file}:`, error)
  }
}

/** Extract a session id from a stream event, if it carries one. */
function sessionIDOf(event: unknown): string | undefined {
  const data = (event as { data?: { sessionID?: unknown } }).data
  return typeof data?.sessionID === "string" ? data.sessionID : undefined
}

export default Plugin.define({
  id: "notchglow",
  async setup(ctx) {
    const options = (ctx.options ?? {}) as { file?: string }
    const file = options.file ? resolve(options.file) : DEFAULT_FILE

    // Track which sessions still have pending permission requests so a reply
    // flips the notch back from RED to yellow while the turn keeps running.
    const pendingPermissions = new Set<string>()
    const running = new Set<string>()

    let lastWritten = await readFile(file, "utf8").then(
      (content) => content.trim(),
      () => "",
    )

    async function setColor(color: string): Promise<void> {
      if (color === lastWritten) return
      lastWritten = color
      await writeColor(file, color)
    }

    const controller = new AbortController()

    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          const sessionID = sessionIDOf(event)
          switch (event.type) {
            case "session.execution.started": {
              if (sessionID) running.add(sessionID)
              if (pendingPermissions.size === 0) await setColor(COLOR.yellow)
              break
            }
            case "permission.asked": {
              if (sessionID) pendingPermissions.add(sessionID)
              await setColor(COLOR.red)
              break
            }
            case "permission.replied": {
              if (sessionID) pendingPermissions.delete(sessionID)
              if (running.size > 0) await setColor(COLOR.yellow)
              break
            }
            case "session.execution.succeeded": {
              if (sessionID) running.delete(sessionID)
              if (running.size === 0) await setColor(COLOR.green)
              break
            }
            case "session.execution.failed":
            case "session.execution.interrupted": {
              if (sessionID) running.delete(sessionID)
              if (running.size === 0) await setColor(COLOR.clear)
              break
            }
          }
        }
      } catch (error) {
        if ((error as Error).name !== "AbortError") console.error("notchglow:", error)
      }
    })()

    return () => controller.abort()
  },
})
