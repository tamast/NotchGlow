import { mkdir, readFile, writeFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"

/**
 * NotchGlow plugin for OpenCode v1 — mirrors agent state into the color file
 * watched by the NotchGlow menu-bar app.
 *
 *   YELLOW — an agent turn is running (busy)
 *   RED    — a permission is waiting for user approval
 *   GREEN  — the last turn finished successfully
 *   CLEAR  — the turn errored out
 *
 * v1 events used (v2's session.execution.* do not exist here):
 *   session.status      { sessionID, status: {type: "busy" | "idle" | "retry"} }
 *   session.idle        { sessionID }            — turn finished OK
 *   session.error       { sessionID?, error? }   — turn failed / aborted
 *   permission.updated  { id, sessionID, ... }   — permission asked
 *   permission.replied  { sessionID, permissionID, response }
 *
 * Install: copy this file to ~/.config/opencode/plugins/notchglow.ts
 * (auto-discovered; every *.ts / *.js one level deep in plugin/ or plugins/
 * is loaded at startup). No dependencies — the `Plugin` type import is
 * commented out so the file works without @opencode-ai/plugin installed.
 *
 * The watched file defaults to ~/.notch-color. To override, convert the
 * plugin to a config entry with options, or edit DEFAULT_FILE below.
 *
 * When several sessions run in parallel, the most recent signal wins.
 */

// import type { Plugin } from "@opencode-ai/plugin"

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

/** Extract a session id from an event's properties, if it carries one. */
function sessionIDOf(properties: unknown): string | undefined {
  const id = (properties as { sessionID?: unknown })?.sessionID
  return typeof id === "string" ? id : undefined
}

export const NotchGlowPlugin = async () => {
  const file = DEFAULT_FILE

  // Sessions with a pending permission request, and sessions mid-turn, so a
  // permission reply flips the notch back from RED to yellow while work goes on.
  const pendingPermissions = new Set<string>()
  const busy = new Set<string>()

  let lastWritten = await readFile(file, "utf8").then(
    (content) => content.trim(),
    () => "",
  )

  async function setColor(color: string): Promise<void> {
    if (color === lastWritten) return
    lastWritten = color
    await writeColor(file, color)
  }

  return {
    event: async ({ event }: { event: { type: string; properties: unknown } }) => {
      const sessionID = sessionIDOf(event.properties)
      switch (event.type) {
        case "session.status": {
          const status = (event.properties as { status?: { type?: string } })?.status
          if (status?.type === "busy" || status?.type === "retry") {
            if (sessionID) busy.add(sessionID)
            if (pendingPermissions.size === 0) await setColor(COLOR.yellow)
          } else if (status?.type === "idle" && sessionID) {
            busy.delete(sessionID)
          }
          break
        }
        case "permission.updated": {
          if (sessionID) pendingPermissions.add(sessionID)
          await setColor(COLOR.red)
          break
        }
        case "permission.replied": {
          if (sessionID) pendingPermissions.delete(sessionID)
          if (busy.size > 0) await setColor(COLOR.yellow)
          break
        }
        case "session.idle": {
          if (sessionID) busy.delete(sessionID)
          if (busy.size === 0 && pendingPermissions.size === 0) {
            await setColor(COLOR.green)
          }
          break
        }
        case "session.error": {
          if (sessionID) {
            busy.delete(sessionID)
            pendingPermissions.delete(sessionID)
          }
          if (busy.size === 0) await setColor(COLOR.clear)
          break
        }
      }
    },
    // Server instance (TUI or `opencode run`) is shutting down — hide the glow
    // so it never gets stuck on after the agent exits.
    dispose: async () => {
      await setColor(COLOR.clear)
    },
  }
}
