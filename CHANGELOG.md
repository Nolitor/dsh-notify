# Changelog — Notify for Chrome (`@nolit/dsh-notify-web`)

<!-- skeleton:
version: 2.0
kind: report
status: active
updated: 2026-11-05
summary: Engineering history for Notify for Chrome (formerly DSH Notify Web). Seeded from git history on 2026-11-04; entries after that date record what changed, why, and the measured before/after, per docs/RULES.md 6.1.
-->

> History lives here (owner instruction 2026-11-04). Boot cards and `AGENTS.md` are narrowed to
> the owner's unfinished asks; they are not a changelog. See [docs/RULES.md](../docs/RULES.md) §6.1.

Current version: `0.0.1-rc.2`

## Seeded history (from git, before this file existed)

The commits below predate this file. They are the record of what shipped, quoted from the
repository history rather than rewritten:

- `50f50d8` harness bootstrap (timestamped boot cards, policy management)
- `56300b7` feat(settings): sorted model checklist, persisted sweep, locale-aware tab labels
- `61c44d8` fix(plugins): native menu typography, grouping and settings panel

## Entries after 2026-11-04

Add newest first. Each entry: what changed, why, and the measured before/after. A change with no
entry here is not complete.

### 2026-11-05 — `0.0.1-rc.2` — Chrome-only rewrite, renamed "Notify for Chrome"

Owner request (translated): *"Notify version management also to 0.0.1.rc2, while removing legacy
things except Chrome notifications; make it follow DSH style and fonts so it does not use anything
of its own; rename to 'Notify for Chrome' (English default, Korean 알림 for 크롬 when the
multilingual locale is Korean); the Chrome notification used on Windows should change according to
the install environment; remove all other legacy system call paths."*

Owner decisions applied (given during the session):

| # | Decision | Applied as |
|---|---|---|
| 1 | Version `0.0.1.rc2` (owner form) | `package.json` version **`0.0.1-rc.2`** — the semver-valid equivalent of the owner-stated `0.0.1.rc2`. The owner form is recorded here verbatim; the semantic version must use the hyphen because npm rejects `0.0.1.rc2`. |
| 2 | Keep the in-app toast as fallback; remove sound engine / BYO audio / self-authored CSS | Chrome notification is primary; the **native DSH toast** is the silent fallback. Web Audio, the inline beep data URI, `<audio>`, BYO audio upload, IndexedDB audio storage and every sound setting are removed. |
| 3 | Windows platform detection (option 1): branch only the Chrome-notification parameters, keep the toast | `detectPlatform()` + `detectInstallState()`; `requireInteraction`/`silent`/tag and the permission guidance branch on platform + install mode. Nothing else is Windows-specific. |
| 4 | Everything visual uses DSH tokens and native settings rows; no own stylesheet | `settings.section` renders native `Switch`/`Button`/`Tag`/`Input`; the fallback renders the native `Toast`; the section icon is the DSH `IconAlarmClockOutlineRegular`; sizes use `--dsh-content-font-*`, colours `--dsw-*`. Zero injected CSS. |
| 5 | Package name | Kept **`@nolit/dsh-notify-web`** — renaming it would break the live profile's `link:` dependency. Only display identity changed: English **Notify for Chrome**, Korean **알림 for 크롬**. |
| 6 | rc.1 compliance (lead) | `engines.node` `>=24` → **`>=24.9`**; cordis peer **`~4.0.6-alpha.1` → `^4.1.0`** (the old range excluded the installed Cordis 4.1.0). |

#### Measured before → after

Measured with `git show HEAD:dsh-notify/...` for before and the working tree for after
(2026-11-05, this workspace).

| Surface | Before (HEAD, 0.1.8) | After (0.0.1-rc.2) | Evidence |
|---|---|---|---|
| Display identity | "DSH Notify Web" / "DSH 알림 (웹)" | "Notify for Chrome" / "알림 for 크롬" | `locale/*.json` `meta.title`, `market/index.json` `title` |
| Version | `0.1.8` | `0.0.1-rc.2` (owner: `0.0.1.rc2`) | `package.json`, `market/index.json` `versions[0]` |
| Notification channels | Chrome notification + Web Audio chime + inline WAV beep + in-app toast queue + tab-title marker | Chrome notification **primary**; native DSH toast **silent fallback**; no audio, no title marker | `lib/client.js` |
| `AudioContext` references | 3 | 0 | `grep -c AudioContext` |
| `indexedDB` references | 4 | 0 | `grep -c indexedDB` |
| Sound settings | `soundEnabled`, `soundSource`, `volume` + BYO audio file | removed (7 boolean rows + cooldown) | `cordis.patch.yml`, client settings |
| Self-authored stylesheet | `NOTIFY_CSS`, 26 `.dshNbx*` rules, injected into `document.head` | 0 bytes of CSS; native primitives + token inline styles | `grep -c 'dshNbx.*{'`, no `document.head` |
| Hardcoded `font-family` | 1 (`var(--ds-font-family, "Segoe UI", …)`) | 0 | `grep -c fontFamily` |
| Hardcoded pixel font sizes | 5 (`fontSize: 12/13/14`) | 0; every size is `var(--dsh-content-font-*, Npx)` and every line height `calc(Npx + var(--dsh-content-font-delta*, 0px))` | `test/typography.test.mjs` |
| Language in code paths | hardcoded Korean (1,009 Hangul chars in `client.js`) | English default; Korean only from the baked dictionary (0 Hangul outside it) | `test/locale.test.mjs` |
| Windows / install environment | not detected; fixed parameters with hand comments | platform + install-mode detection; parameters branch per environment | `notificationOptionsFor()`, `test/client.test.mjs` |
| Cordis peer | `~4.0.6-alpha.1` (excludes installed 4.1.0) | `^4.1.0` | `package.json` |
| `engines.node` | `>=24` | `>=24.9` | `package.json` |
| Browser-half lines | 1,774 | 1,321 generated (`lib/client.src.js` 1,162 handwritten) | `wc -l` |
| Tests | 25 (`client` 21 + `typography` 4), no locale/manifest contract | 51 across four files (`client` 25, `typography` 7, `locale` 7, `manifest` 12) | `npm test` |

Legacy paths removed from the shipped client: Web Audio synthesis, inline WAV data URI, `<audio>`
element playback, BYO audio upload/decode/IndexedDB store, volume/source/sound toggles, the
`<style>` injection, the first-use consent card, the tab-title alert marker, and the hardcoded
Korean UI strings. The historical `prototype-windows/` tree and `docs/` files are not shipped in the
package (`package.json` `files`) and are not referenced by the notification code path; they remain
as project history only.

#### Verification

Isolated-`DSH_HOME` boot recipe (run 2026-11-05, DSH `0.2.2-rc.1`, Node v24.22.1, Chromium
1248 headless, Playwright core 1.64.1): a copy of `~/.dsh/profiles/web` under the workspace, with
the copied patch's session-search `path:` pointed into the copy and a disabled
`tokeneconomizer-dsh` row; temp home removed afterwards. Live profile untouched.

| Check | Measured result |
|---|---|
| `npm test` (pretest regenerates locale + client) | **51/51 pass, 0 fail** |
| `node --check` on `lib/client.js`, `lib/client.src.js`, `scripts/*.mjs` | pass |
| `lib/client.js` regenerated from `lib/client.src.js` + `locale/*.json` | build fails if the placeholder survives; a test asserts the baked table equals the JSON |
| Boot, English (locale preference `en`) | **0 page errors**, no `did not activate`; nav label **Notify for Chrome**; section heading **Notify for Chrome**; **7 native `[role="switch"]`** rows with English labels; **0** plugin `<style>` tags |
| Boot, Korean (locale preference `ko`) | **0 page errors, 0 console errors**; nav label **알림 for 크롬**; **7 native switches** with Korean labels; section text Korean; **0** plugin `<style>` tags |
| Typography in the real boot | section root computed `font-size: 12px` = `--dsh-content-font-size` (profile sets 12); `font-family` is the host/Korean-pack stack (inherited), never a plugin stack |
| Chrome-notification path with granted permission | `Notification.permission === 'granted'`; test action returns channel `chrome`, `lastDelivery.osShown === true`, no toast |
| Fallback path when Chrome cannot show it (permission `default`/blocked) | test action returns channel `fallback`, `osShown === false`, and the **native DSH toast** renders with the localized text (measured `알림 테스트 — 크롬 알림이 정상 동작합니다.` in the Korean boot) |
| Plugin activation | `window.__dshNotifyChrome` present in both boots (the browser half ran `apply()`) |
| Live profile | untouched; change is **applied pending restart** (the owner restarts) |

#### Follow-ups / notes

- Browser notification preferences remain in `localStorage` (version 2), not the Host settings
  service. The plugin's Host half is intentionally a no-op and exposes no settings namespace; the
  preferences are browser-side (permission, tab leadership, toast fallback) and must work before
  any Host form round-trip. Recorded as an assumption; moving them to a Host `Config` + `configForms`
  namespace would add a Host-side schema dependency and a new required client service.
- The owner's "remove all other legacy system call paths" is satisfied for the shipped plugin; the
  historical Windows prototype is not a runtime path and was left in place after the lead narrowed
  the legacy-removal scope to sound/BYO/self-CSS.
