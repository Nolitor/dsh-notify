# RECOVERY NOTES — what was restored, how, and what is still missing

<!-- skeleton:
version: 1.0
kind: reference
status: reference
updated: 2026-10-24
summary: What was restored into this track, how it was restored, and which pieces are still missing.
-->


> Track: `dsh-plugins/dsh-notify` · recovery date: 2026-10-24 · sources: 8 DSH session logs (see `../PROVENANCE.md`)

This document is the honest gap report for the reconstruction. Nothing below was invented: every
restored file comes from a `write`/`edit` tool call, a full-file `read` tool result, or an
explicit shell mutation captured in the session logs.

## 1. Files missing from the replayed staging tree, now recovered

The staging replay (`/tmp/reconstruct/notify`) only replayed `write`/`edit` tool calls, so files
created before logging started (or mutated only through PowerShell here-strings) were absent or
stale. The following were recovered and **verified against every later `read` snapshot** (0 line
mismatches at each check):

| File | Status | Evidence used |
|---|---|---|
| `docs/BOOT-CARD.md` | **recovered, 167 lines** | full `read` at session a3b2bf75 seq 39 (113 lines) → replayed through 12 later `edit` calls + 1 PowerShell `Replace` (milestone-3/final status block); all 5 later read snapshots match |
| `docs/2026-10-20-dsh-notify-design.md` | **recovered, 326 lines** | full `read` at a3b2bf75 seq 51 (260 lines) → replayed through 25 later `edit` calls + 2 PowerShell `Replace` calls; all 16 later read snapshots match |
| `docs/deepseek-peak-spec.md` | **recovered, 361 lines** | full `read` at a3b2bf75 seq 57 (258 lines) → replayed through 15 later `edit` calls; all 12 later read snapshots match |
| `README.md` (now `prototype-windows/README.md`) | **recovered, 156 lines** | full `read` at b53400d8 seq 46 (115 lines, already post-dates earlier shell mutations) → replayed through 14 later `edit` calls; all 4 later read snapshots match |
| `.gitignore` (now `prototype-windows/.gitignore`) | **recovered, 18 lines** | full `read` at b53400d8 seq 2621; one later logged `edit` applied |
| `plugin/market/icons/dsh-notify.svg` (now `market/icons/dsh-notify.svg`) | **recovered** | log shows it was created by `Copy-Item plugin/icon.svg → plugin/market/icons/dsh-notify.svg` (b53400d8 seq 959); recreated as that byte-identical copy of `icon.svg` |
| `plugin/LICENSE` (now root `LICENSE`) | **recovered verbatim** | written by `write` (MIT, "Copyright (c) 2026 nolit"); the in-log `Copy-Item LICENSE → plugin/LICENSE` is the same text |
| `ui/assets/digital-7-license.txt` | **recovered, full text** | full `read` result in a3b2bf75; the `.ttf` binary itself is unrecoverable (see §3) |
| `docs/2026-10-20-final-status.md`, `docs/dsh-harness-notify-spec.md`, `prototype-windows/bridge/index.js`, `prototype-windows/notify/popup.ps1`, `prototype-windows/tests/docs-contract.ps1` | **refreshed to last verified state** | staging was stale for these five; replaced with the latest full `read` snapshot taken after their last mutation (b53400d8, 2026-10-22 18:28–19:37) |

## 2. PowerShell in-place mutations that a write/edit replay cannot see

The staging replay captured the `write`/`edit` tools but not shell commands such as
`[IO.File]::WriteAllText(...)` / `$text.Replace(...)` / `Set-Content`. Mutations that were
verifiable and not superseded by a later `write`/`edit` were re-applied by hand:

- `prototype-windows/tests/core-config.ps1` — default opacity expectation 0.82 → 0.6 and
  `'현지 18:00–21:00 (UTC-7)'` → `'Local 18:00–21:00 (UTC-7)'` (a3b2bf75 seq 2456/2896/2922;
  confirmed by the b53400d8 read at 19:33).
- `prototype-windows/tests/presenter.ps1` — opacity 0.82 → 0.6, title expectations
  `'DeepSeek 피크 (100%)'` → `'DeepSeek Peak (100%)'` / `'DeepSeek 오프피크 (50%)'` → `'DeepSeek Off-Peak (50%)'`.
- `prototype-windows/tests/indicator-render.ps1` — brightness threshold 140 → 100
  (a3b2bf75 seq 3073, after the file's last write).
- `prototype-windows/ui/render-indicator.ps1` — local label `현지 18:00–21:00 (PDT)` →
  `Local 18:00–21:00 (UTC-7)`.
- `prototype-windows/start.cmd` — rewritable shell entry point was replaced by a here-string
  command (b53400d8 seq 2731: adds `chcp 65001`, UIPI re-launch guard, `app\core.ps1` fallback);
  restored with the logged content and CRLF line endings.

Files whose staging content was already produced by a later `write`/`edit` were deliberately
**not** patched (e.g. `config.ps1`, `ui/presenter.ps1`, `ui/indicator.ps1`), to avoid
overwriting authoritative tool-call content with an older shell edit.

**Residual risk:** for a handful of prototype files the last logged event is a shell mutation
whose exact resulting text is not fully verifiable from a later read (e.g. hand-edited EOL/BOM
changes). Those files keep the staging content; they may differ from the Windows machine's final
bytes by whitespace/encoding only. They are never executed by this track.

## 3. Not recoverable (no content in any session log)

These runtime/generated assets are referenced by the recovered prototype but their bytes are not
in the logs. **No placeholder files were fabricated:**

- `ui/assets/digital-7.ttf` (user-supplied font, licence text was recovered)
- `ui/assets/deepseek-logo.png` (user-supplied DeepSeek wordmark)
- `ui/icons/*.ico` and `ui/icons/preview.png` (generated by `ui/build-icons.ps1` / `ui/icons.ps1`)
- `ui/previews/indicator-alert.png`, `ui/previews/indicator-ok.png` (rendered screenshots)
- `notify/ding.wav`, `cache/ding-custom.wav` (generated audio; later removed under the BYO asset policy)
- `cache/deepseek-peak/2026.json` (holiday data fetched from GitHub at runtime),
  `cache/region.json`, `cache/*.log`, `config.json`, `runtime.json`, `events.jsonl`
- `DSH-Notify.exe` and `dist/DSH-Notify-Portable*` build outputs
- `docs/previews/*.png` images referenced by the design doc
- `THIRD-PARTY-NOTICES.md` — no such file appears in any of the eight session logs (the project
  tracked third-party notices in `docs/2026-10-23-asset-policy.md` instead), so none was created.

`prototype-windows/cache/.gitkeep` is the one intentional **empty file** in this track: it is the
recovered git keep-marker for the runtime cache directory (it was 0 bytes in the original repo).

## 4. Structural notes / deliberate deviations

- The original project was one tree (`README.md`, `docs/`, `core.ps1`, `plugin/`, …). This track
  promotes the **plugin package** to the root (as requested for the unified workspace) and moves
  everything else under `prototype-windows/`. The project `docs/` folder is promoted to
  `../docs/` (track root) rather than `prototype-windows/docs/`.
- Because of that move, some recovered relative links no longer resolve inside this track
  (e.g. plugin `README.md`'s `../docs/…` link, prototype `README.md`'s `docs/…` links). The text
  is preserved verbatim; links were **not** rewritten.
- `package.json` was recovered verbatim except for one manifest-metadata change: 
  `"test/client.test.mjs"` was added to the `files` array so the committed test file is covered
  by the package manifest. No runtime behavior, exports, or DSH metadata changed.
- `market/icons/dsh-notify.svg` is a copy of `icon.svg`, matching the original `Copy-Item`.
- `prototype-windows/LICENSE` duplicates the root MIT licence because the original project root
  carried the same licence file.

## 5. Validation performed on this track (2026-10-24, Linux, Node.js v24.2.0)

- JSON: all 5 JSON files parse (`node -e JSON.parse(...)`) — **PASS**.
- ESM: all 6 `.js`/`.mjs` files parse as ESM (`node --input-type=module --check < file`) — **PASS**.
- Tests: `node --test test/client.test.mjs` — **15 passed / 0 failed** (browser APIs are mocked; no
  DOM/jsdom needed). The plugin also self-reports `exports.__test` for headless core checks.
- Manifest: `dsh.manifestVersion = 1`, `dsh.client.platform = "web"`, `exports["./client"] = "./lib/client.js"`,
  `files` covers every package file — **PASS**.
- PowerShell/JScript was **not** executed: `pwsh`/WPF/`wscript` are Windows-only and unavailable on
  this Linux host. The prototype is preserved as source, not validated by execution.
- No network access, no package installation, no writes outside this track and `/tmp`.
