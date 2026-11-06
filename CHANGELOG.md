# Changelog — Notify for Chrome (`@nolit/dsh-notify`)

<!-- skeleton:
version: 2.0
kind: report
status: active
updated: 2026-11-06
summary: Engineering history for Notify for Chrome (formerly DSH Notify Web). Seeded from git history on 2026-11-04; entries after that date record what changed, why, and the measured before/after, per docs/RULES.md 6.1.
-->

> History lives here (owner instruction 2026-11-04). Boot cards and `AGENTS.md` are narrowed to
> the owner's unfinished asks; they are not a changelog. See `docs/RULES.md` §6.1 in the `dsh-plugins` workspace.

Current version: `0.0.1-rc.3`

## Seeded history (from git, before this file existed)

The commits below predate this file. They are the record of what shipped, quoted from the
repository history rather than rewritten:

- `50f50d8` harness bootstrap (timestamped boot cards, policy management)
- `56300b7` feat(settings): sorted model checklist, persisted sweep, locale-aware tab labels
- `61c44d8` fix(plugins): native menu typography, grouping and settings panel

## Entries after 2026-11-04

Add newest first. Each entry: what changed, why, and the measured before/after. A change with no
entry here is not complete.

### 2026-11-06 — `0.0.1-rc.3` — package renamed to `@nolit/dsh-notify`

Owner instruction: the npm package name must be `@nolit/dsh-notify`. The `-web`
suffix was never the owner's choice and the owner was never told the package
carried it.

What the measurement showed, and what had been misreported:

| Claim | Reality |
| :--- | :--- |
| `CHANGELOG.md` entry for `0.0.1-rc.2` said the package name was **"Kept `@nolit/dsh-notify`"** | The name on disk was `@nolit/dsh-notify-web` in **every commit** since the repository's first commit `50f50d8` (2026-10-29, v0.1.6). `@nolit/dsh-notify` had **never existed** here: `git log -S'@nolit/dsh-notify"'` returns 0 commits. The "Kept" entry was a false record and is corrected in place. |
| `PROVENANCE.md` documents the package as `@nolit/dsh-notify` | Also never matched disk. The recovered tree was created as `-web`, so the two disagreed from 2026-10-24 onward and nobody reconciled them. |
| Release artifacts | `nolit-dsh-notify-web-0.1.6/7/8.tgz`, and the `name` inside each tarball was `@nolit/dsh-notify-web`. |

Renamed surfaces (before → after):

| Surface | Before | After |
| :--- | :--- | :--- |
| `package.json` `name` | `@nolit/dsh-notify-web` | **`@nolit/dsh-notify`** |
| `market/index.json` `plugins[0].name` | `@nolit/dsh-notify-web` | **`@nolit/dsh-notify`** |
| `cordis.patch.yml` row `name` | `@nolit/dsh-notify-web` | **`@nolit/dsh-notify`** |
| `lib/client.src.js` module `id` | `@nolit/dsh-notify-web` | **`@nolit/dsh-notify`** |
| `test/manifest.test.mjs` assertions | `@nolit/dsh-notify-web` | **`@nolit/dsh-notify`** |
| `scripts/install-notify-live.sh`, `scripts/publish-npm.sh` | `@nolit/dsh-notify-web` | **`@nolit/dsh-notify`** |
| Docs (track + workspace, 11 files) | `@nolit/dsh-notify-web` | **`@nolit/dsh-notify`** |

Deliberately **not** changed: the `cordis.patch.yml` row **`id: dsh-notify-web`**.
It is a plugin-row identifier, not the package name, and the owner did not ask
for it. An earlier attempt in this session changed it to `notify`; that was
outside the instruction and was reverted before committing.

Version is unchanged at `0.0.1-rc.3`. Version numbers belong to the owner.

Gates after the rename: `npm test` 69/69; `scripts/check-npm-publishable.mjs`
exit 0; `npm run docs:check` 1,242 links OK.

### 2026-11-06 — `0.0.1-rc.3` — published to GitHub (`Nolitor/dsh-notify`)

The track had no repository of its own; it lived only as a directory inside the
`dsh-plugins` superproject, which has no remote. `Nolitor/dsh-notify` existed
but held the **Windows prototype** with the web plugin nested under `plugin/`
and an unrelated history (root commit `6f63d06`, no shared objects).

Owner decision: **option C** — replace `main` with this plugin, keeping the
Windows prototype recoverable.

Measured before → after:

| Surface | Before | After |
| :--- | :--- | :--- |
| `Nolitor/dsh-notify` `main` | `aa4dd9c` — Windows prototype at root, plugin in `plugin/` @ `0.2.1` | **`9641ff5`** — this plugin at root @ `0.0.1-rc.3` |
| History | unrelated to the superproject | 7 commits split from `dsh-notify/` via `git subtree split` |
| Root tree | `app/ bridge/ build/ core.ps1 ... plugin/` | `CHANGELOG.md LICENSE PROVENANCE.md README.md cordis.patch.yml docs icon.svg lib locale market package.json prototype-windows scripts test` |
| Windows prototype | at root | preserved under `prototype-windows/` **and** in tag `archive/windows-prototype-v0.2.1` |

Safety net: tag `archive/windows-prototype-v0.2.1` was pushed **before** the
force-push, so every pre-existing file — including `ui/icons/*.ico`, which
`docs/RECOVERY-NOTES.md` §3 records as unrecoverable from the session logs —
stays retrievable. The force-push used `--force-with-lease` against the exact
commit measured (`aa4dd9c`).

The split was verified faithful: the split branch tree
(`391c367f235c11e61badb297e8223cb6c1fe4a3f`) is byte-identical to
`HEAD:dsh-notify`.

Not changed, and why: `docs/` still contains absolute paths (`/home/minami` ×2,
`C:\Users\nolit` ×16). They sit in measurement and design documents as evidence
of the defects being reported, so removing them would destroy the record. Runtime
code (`lib/`, `scripts/`, `locale/`, `market/`) has **zero** absolute paths.

### 2026-11-06 — `0.0.1-rc.3` — 7-segment peak countdown chip

Owner instruction (translated): *"If the window cannot be force-promoted, strengthen the in-app UI.
Implement a 7-segment digital countdown floating widget (or fixed chip) inside the DSH screen
showing DeepSeek off-peak/peak time remaining, reusing the Windows prototype's 7-segment style.
Green off-peak countdown by default, colour/state change at peak. Background tabs announce the flip
through the already-verified Chrome notification plus `setAppBadge`."*

Owner decisions in the same turn:

| # | Decision | Applied as |
|---|---|---|
| 1 | Makeup workdays are **off-peak** | `treatMakeupAsPeak` does not exist in the browser half; a `isOffDay: false` date returns `{ isPeak: false, reason: 'makeup-workday' }`. The Windows prototype's `true` default is **not** carried over. |
| 2 | Version `0.0.1.rc3` | `package.json` / `market/index.json` = **`0.0.1-rc.3`** (semver form of the owner's `0.0.1.rc3`). |

#### What was added

- **Peak engine (pure, testable).** `peakDecision`, `peakNextChange`, `peakTimerText`,
  `peakHolidayIndex`, `beijingDateKey` — a port of the measured Windows provider. Peak windows are
  the fixed UTC definition (01:00–04:00, 06:00–10:00, Mon–Fri, excluding Chinese public holidays);
  holiday matching uses the **Beijing calendar day (UTC+8)** because the published dates are State
  Council local dates.
- **7-segment chip.** Inline SVG traced from the prototype's geometry (10×18 unit box, 1.9 unit
  round-cap stroke). No font, no `font-family`, no stylesheet; every stroke is a `--dsw-*` token.
  Colour is `--dsw-alias-state-success-primary` off-peak and `--dsw-alias-state-error-primary` at
  peak.
- **Mount seat.** Registered into `conversation.session.header.utilities` — measured 2026-11-06 as a
  `list`-kind, `replaceRisk: none` seat already rendering three entries, so an additive cell needs no
  priority trick. The chip is `order: 10`.
- **Transition announcement.** On a state flip it reuses the single notification channel (Chrome
  first, native toast fallback) and sets/clears `setAppBadge` plus a `●` tab-title marker.
- **Two settings rows**, both defaulted on: *Show peak countdown chip* and *Announce peak changes*.
  They are declared in `cordis.patch.yml` as well, because the manifest contract requires the patch
  to configure exactly what the client normalizes.

#### Measured before → after

| Surface | Before (rc.2) | After (rc.3) | Evidence |
|---|---|---|---|
| Peak awareness | none (0 references) | decision + countdown + announcement | `lib/client.js`, `test/peak.test.mjs` |
| Destination slot | none | `conversation.session.header.utilities` (list) | `cordis_inspect_query` live occupancy |
| Settings keys | 8 | 11 | `DEFAULT_SETTINGS`, `cordis.patch.yml` |
| Locale keys | 74 per language | 99 per language | `locale/en.json`, `locale/ko.json` |
| Tests | 51 | 69 | `npm test` |
| Version | `0.0.1-rc.2` | `0.0.1-rc.3` | `package.json`, `market/index.json` |

#### Bug fix — route gate (owner report, same session)

The chip shipped in this version initially rendered for **every** model route. The owner reported it
while the session was on `opencode-http-agent`:

> "지금 다른 같은 딥시크이지만 공식이 아닌 딥시크 모델인데 저게 뜨는데? … 공식 모델 쓸때만 보여야
> 할텐데?"

The peak/off-peak clock is a property of **DeepSeek's own billing**. A gateway, reseller or proxy
route has its own price sheet, so the chip was stating a price the user was not paying.

**Fix.** The chip, the transition announcement, the tab badge and the title marker now all require an
official route:

| Surface | Gate |
|---|---|
| Chip render | `if (!onOfficialRoute) return null` |
| `setAppBadge` / tab title `●` | only while an official route is active |
| Transition notification | `if (!isOfficialDeepSeekProvider(...)) return` |

Official ids, read from the packages that register them (measured 2026-11-06):
`dsh-llm-deepseek-api-key` -> **`deepseek-official`**, `dsh-llm-deepseek-account` ->
**`deepseek-account`**.

The live selection is read from `[data-provider-id][data-model-id]` — the attribute pair the model
selector stamps on its trigger (`dsh-client-ui-model-selection`, `renderModelLabel`, placement
`trigger`), which is the same read path DeepInfra's cost chip uses. An attribute-filtered
`MutationObserver` follows route changes; no polling.

Live profile note: `llm-deepseek` is `disabled: true` and the default model is
`opencode-http-agent / opencode-go/deepseek-v4.1-flash`, so **the chip is correctly hidden in the
owner's current setup** and appears only after switching to an official route.

#### Settings restructure + opt-in toggle (owner decision, same session)

Owner instruction (translated): *"Add a 'show even when not an official route' toggle as a setting.
In the Notify for Chrome settings tab, show it as two categories — the DeepSeek peak timer, and
notifications. Only `deepseek-official` / `deepseek-account` are checked by default; other users'
ids may differ, so when the option is on, show every other route too; when off, only those two.
Stay within DSH conventions, and state in the install docs that DeepSeek's discount is declared for
its own service and other services may differ even for the same model."*

| # | Decision | Applied as |
|---|---|---|
| 1 | Two setting categories | The page now renders four cards: **Chrome status**, **알림 조건**, **딥시크 피크 타이머**, **환경**. The peak rows moved out of the notification card into their own. |
| 2 | Opt-in toggle for other routes | New setting `peakOnAnyProvider`, **default `false`**, row label *Show timer on other providers*. |
| 3 | Only official ids by default | `peakAppliesToRoute(providerId, settings)` returns the official check unless the toggle is `true`. Used by the chip, the announcement, and the badge/title marker alike. |
| 4 | State the caveat in the install docs | README §4 gains *The peak timer only trusts official DeepSeek routes by default*, and the settings card carries the same warning inline. |

The caveat as shipped: DeepSeek publishes the off-peak discount for **its own API**; a different
service serving the same model may bill differently, so the timer is a reference there, not a fact.

`peakAppliesToRoute` accepts only a literal `true` for the opt-in, so a stray truthy string from
`localStorage` cannot silently widen the gate (asserted in `test/peak.test.mjs`).

#### Copy + order correction (owner report, same session)

Owner instruction (translated): *"Replace it with this wording in settings, and you know it shows
differently for English and Korean. And swap the peak-timer and notification order."*

| # | Change | Applied as |
|---|---|---|
| 1 | Caveat text replaced with the owner's exact sentence | `locale/ko.json` carries the Korean verbatim; `locale/en.json` carries the English translation. Both are baked by `gen-locale.mjs`, so the two languages stay in sync by construction. |
| 2 | Peak timer card moved **above** notifications | Card order is now: Chrome status → **DeepSeek peak timer** → notifications → environment. |

A defect found while doing this: the **completion-cooldown row** had been left inside the peak card
when the categories were first split. It belongs to notifications and has been moved back, so the
peak card now holds only the three peak rows and its caveat.

Owner wording, as shipped (ko):

> 딥시크는 공식 모델 API에 대해서만 할인을 명시합니다. 같은 모델이라도 다른 제공자는 서비스 요금이
> 다를 수 있으며 보장하지 않습니다. 그 경우 이 타이머는 참고 사항일 뿐입니다.

Verified by rendering the real settings component in Chromium for both locales:
`[크롬 알림, 딥시크 피크 타이머, 알림 조건, 환경]` and
`[Chrome notifications, DeepSeek peak timer, When to notify, Environment]`.

#### Label clarification — "Platform" was ambiguous (owner question, same session)

Owner asked what the environment card's **Platform** row means — *"is it the remote platform or the
local platform that is currently running?"* — because it showed **Windows** while the DSH host runs
on Linux.

**Measured answer:** it is the **browser's** OS, never the host's.

| Evidence | Result |
|---|---|
| `uname -srm` on the host | `Linux 7.1.5-... x86_64` (Pop!_OS 24.04) |
| `detectPlatform` inputs | `documentElement.dataset.platform`, `navigator.userAgentData.platform`, `navigator.platform`, `navigator.userAgent` — all browser-side |
| Is the host OS exposed to the client? | **No.** No client Service or `@Remote` method returns the host platform (`terminalController.environment` returns terminal geometry only) |
| Feeding it a real Linux Chrome UA | `{"platform":"linux","installState":"browser"}` — the detector is correct |
| So "Windows" on a Linux host means | the Chrome tab itself runs on Windows |

That is the correct value, because every rule the platform feeds is a **browser** property:
`requireInteraction` support, Action Center persistence, and the installed-app branch.

**Fix (label, not logic).** The row is renamed `Platform` -> **Browser OS** (브라우저 OS) and now
carries an inline hint: *"The operating system of the machine running this browser tab — not the
machine running the DSH host. Notification behaviour depends on this one."* The detection code is
unchanged; it was already right.

Also corrected: an earlier `docs/` note implied the platform was the host's. The README now states
the browser/host split with the measured per-OS behaviour table.

#### Browser support + security disclosure (owner instruction, same session)

Owner challenge (translated): *"The plugin is Chrome-based, so why care about the OS platform?
Unless you check the Chrome version... but you should state that operation is not guaranteed outside
Chrome. And you should document the Chrome security issues too — a popup may not appear because of
security."*

Correct on both counts.

**A. OS platform was not added by this session.** `detectPlatform` predates it — `git log -S
"function detectPlatform"` pins it to **00e4eb9 (2026-11-05)**, and the earlier rename was a label
fix only. It stays because it is load-bearing: four `notificationOptionsFor` branches key on it
(Windows installed app vs browser tab, `requireInteraction` support, macOS ignoring it). It is not
decoration.

**B. There was no browser check at all.** Measured: zero `Chrome/`, `Edg/`, `Firefox/`, `Safari/`
matchers in the shipped code. Feature detection existed (`Notification`, `isSecureContext`,
`navigator.locks`, `setAppBadge`) but nothing told the user *"this browser is not the target one"*. A
Firefox tab reported `permission: 'default'` and looked healthy while silently ignoring
`requireInteraction`.

**Added:** `detectBrowser()` → `chromium | firefox | safari | other`, surfaced in a new **Browser
support** card in settings with a native `Tag` (Chromium = `success`, anything else = `warning`).
Edge, Opera and Brave are recognised as Chromium because their UAs keep the `Chrome/` token.

Note the exact-version check the owner floated is deliberately **not** done: the plugin's real
minimum is `setAppBadge` (Chrome 81), and a version gate that hides the plugin on a working older
Chrome would be worse than a documented recommendation.

**C. Security constraints documented** (README §6, measured in Chromium 156):

| Constraint | Measured behaviour |
|---|---|
| permission `default` | `new Notification(...)` **does not throw** — it looks successful and shows nothing. The plugin checks `permission === 'granted'` *before* constructing, so it routes to the toast. |
| permission `denied` | `requestPermission()` resolves `'denied'` immediately; Chrome never prompts that origin again. Enable button hidden, because a control that cannot work is not rendered as broken. |
| insecure origin | no OS notifications on `http://<LAN-IP>`; toast fallback. |
| no user gesture | `requestPermission()` auto-denied; driven from the Enable button only. |
| OS Do Not Disturb / Focus Assist, site mute | page cannot override or detect. |
| tab closed | no service-worker backend, no delivery. |

**D. Four stale README claims fixed** while checking the above:

| Claim | Reality |
|---|---|
| "No `fetch`" | the peak timer fetches the holiday list — now disclosed with exactly what is sent (nothing but the request) and how to disable it |
| privacy list omitted the holiday cache | now lists all three `localStorage` keys |
| limitations implied notifications degrade transparently | now names the silent-drop cases |

#### Verification

`npm test` → **69/69 pass**. The new suite re-runs the published spec §5 table and asserts case #7
now expects `false` (makeup workday off-peak), plus the fixed UTC windows, the Beijing-day boundary,
malformed-payload rejection, the 8-day next-change scan, `HH:MM:SS` clamping, and that the rendered
SVG carries token colours only.

**Not verified:** a live pixel render inside the DSH GUI. The GUI requires the `dsh web` auth token,
which is not readable from this session, so the chip has been verified by unit test and by the live
Slot/Service inspections only.

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
| 5 | Package name | Recorded at the time as "Kept **`@nolit/dsh-notify`**". **This was wrong and is corrected on 2026-11-06:** the name on disk was `@nolit/dsh-notify-web` throughout, and `@nolit/dsh-notify` had never existed in this repository's history (`git log -S'@nolit/dsh-notify"'` → 0 commits). Only display identity changed: English **Notify for Chrome**, Korean **알림 for 크롬**. The package was renamed to `@nolit/dsh-notify` by owner instruction on 2026-11-06. |
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
