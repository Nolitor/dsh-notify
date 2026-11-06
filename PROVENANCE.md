# PROVENANCE — dsh-notify track

<!-- skeleton:
version: 1.0
kind: reference
status: reference
updated: 2026-10-24
summary: Where the dsh-notify source tree came from: recovery path out of historical DSH session logs and what could not be recovered.
-->


> Workspace track: `dsh-plugins/dsh-notify` · origin: **DSH Notify** (Windows project) · recovery date: 2026-10-24

This directory is **not** a from-scratch reimplementation. It is a physical promotion of a
Windows-era DSH project that survived only as agent session logs. The original working tree
(`C:\Users\nolit\Workspace\projects\DSH Notify`) no longer exists; the eight session logs
below are the only surviving copy, and every file here was reconstructed from those logs (plus
the staging tree `/tmp/reconstruct/notify`, which was itself replayed from the same logs).

## Source sessions (only surviving copy)

All eight decoded session logs were read from `/tmp/notify-decoded/*.jsonl` (zstd originals under
`~/.dsh/sessions/--home-minami-Workspace-projects-DSH~0020Notify--/`):

| # | Session id | Wall-clock range (UTC) | Events | Role |
|---|---|---|---|---|
| 1 | `session-f9c95dba-191d-4096-94c6-be35c1f8ef4b` | 2026-10-19 16:24 | 5 | empty (header only) |
| 2 | `session-a3b2bf75-8959-4a8e-8b53-9d4394b898e3` | 2026-10-19 16:31 → 2026-10-22 11:20 | 5,854 | **main build session** (PowerShell prototype) |
| 3 | `session-58a2dc78-0e98-49ac-8f3a-beec8a2997c6` | 2026-10-19 16:30 → 2026-10-20 03:44 | 13 | empty (no tool calls) |
| 4 | `session-c7a8072b-507d-4679-833c-3952f3b041c6` | 2026-10-20 04:08 | 5 | empty (header only) |
| 5 | `session-318f99bb-f0dd-462a-8540-3cb7d3694e2d` | 2026-10-20 04:08 | 5 | empty (header only) |
| 6 | `session-21197fd9-a032-4cbd-b5b5-cd0882ce3fe9` | 2026-10-20 04:09 | 5 | empty (header only) |
| 7 | `session-95a9341d-a091-4a4b-879d-899cb432b9cc` | 2026-10-22 18:23 → 2026-10-23 00:49 | 12 | empty (no tool calls) |
| 8 | `session-b53400d8-41db-4a3b-b611-a14f43e62916` | 2026-10-22 18:25 → 2026-10-24 01:28 | 6,044 | **final session** (DSH web plugin half) |

Only sessions 2 and 8 contain recoverable work; the other six carry session headers and commands
but no file-mutating tool calls.

## Recovery method

1. **Decode** all eight `.jsonl` session logs (one event per line, DSH session format v4).
2. **Replay** every `write`/`edit` tool call in wall-clock order onto a staging tree
   (`/tmp/reconstruct/notify`), which is the baseline copied here.
3. **Fill gaps** that replay cannot produce — files created before logging began or mutated
   through shell here-strings rather than `write`/`edit`:
   - `docs/BOOT-CARD.md`, `docs/2026-10-20-dsh-notify-design.md`,
     `docs/deepseek-peak-spec.md`, `README.md`, `.gitignore` — restored from full-file
     `read` tool results, then replayed through every later logged `edit` and every
     verifiable in-place PowerShell mutation.
   - `market/icons/dsh-notify.svg` — the session log shows it was created with
     `Copy-Item plugin/icon.svg → plugin/market/icons/dsh-notify.svg`; recreated as that copy.
   - `LICENSE` — captured verbatim; the `plugin/LICENSE` copy is the same MIT text.
   - `ui/assets/digital-7-license.txt` — recovered from a full read; the font binary itself was
     never in the logs (see `docs/RECOVERY-NOTES.md`).
4. **Verify**: every reconstructed doc was checked against every later `read` snapshot in the
   sessions (0 line mismatches); all JSON/JS files are syntax-checked (see validation in
   `docs/RECOVERY-NOTES.md`).
5. **Promote** the plugin half to this track root; the Windows half is preserved under
   `prototype-windows/` with its original relative structure.

## What is Windows-only vs platform-neutral

**Windows-only (prototype-windows/)** — a PowerShell 7 + WPF resident desktop prototype:
- Requires Windows 10/11, `pwsh.exe`, .NET/WPF (`PresentationFramework`), Windows Forms tray,
  `wscript.exe`/JScript, `start.cmd`, registry-free Startup shortcut. It **cannot run on Linux**
  and no PowerShell/JScript execution was attempted here.
- It also shipped a DSH *host plugin* bridge (`bridge/index.js`, a Node ESM cordis plugin) that
  forwarded DSH events to the Windows popup app via a JSON file. That bridge is part of the
  Windows half because its consumer is the PowerShell app.
- Binary assets that were generated or fetched at runtime are not recoverable from logs
  (fonts, ICOs, PNG previews, ding.wav); see `docs/RECOVERY-NOTES.md`.

**Platform-neutral (this package root)** — `@nolit/dsh-notify` is a browser-only DSH web
plugin: `lib/index.js` is a no-op Host half, all behavior is in `lib/client.js` (Web
Notification + Web Audio + `localStorage`/`IndexedDB`, no ports, no IPC, no filesystem, no
bundled audio/fonts/icons). This half is usable on Linux/macOS/Windows in any Chromium-class
browser and was validated here with Node.js (JSON/ESM parse + `node --test`).

## Layout of this track

```
dsh-notify/
  package.json          # @nolit/dsh-notify (dsh.manifestVersion 1, dsh.client.platform web)
  cordis.patch.yml      # bundle layer that activates the no-op host half
  lib/index.js          # no-op host half
  lib/client.js         # browser half (notifications, settings section, overlay)
  locale/{en,ko}.json   # localization metadata
  market/index.json     # market catalog entry (+ market/icons/dsh-notify.svg)
  icon.svg              # neutral clock icon (no trademark)
  test/client.test.mjs  # browser-API mock tests (node --test)
  README.md             # plugin docs (recovered verbatim)
  LICENSE               # MIT, Copyright (c) 2026 nolit
  prototype-windows/    # recovered Windows PowerShell/WPF prototype (not runnable on Linux)
  docs/                 # recovered project docs (promoted to track root per workspace layout)
  PROVENANCE.md         # this file
```
