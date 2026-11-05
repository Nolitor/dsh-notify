# Notify for Chrome

<!-- skeleton:
version: 2.0
kind: readme
status: active
updated: 2026-11-05
summary: Operator manual and behavior contract for Notify for Chrome (Korean: 알림 for 크롬) — Chrome/Web Notification only, silent in-app toast fallback, native DSH settings rows and typography, Windows/install-mode notification branches.
-->

> Status: active · Updated: 2026-11-05 · Package: `@nolit/dsh-notify-web` v`0.0.1-rc.2` · Korean display name: **알림 for 크롬** · Parent: [README.md](../README.md)

**Notify for Chrome** turns DeepSeek Harness events into **Chrome notifications** (the Web
Notification API, `new Notification(...)`). It has no native app, no ports, no IPC, no file queue
and no system notifier. When Chrome cannot show a notification, the plugin falls back to a
**silent in-app toast**.

## 1. Behavior

| DSH event | Channel |
|---|---|
| `api-session/status` (`running=false`) | Chrome notification "Turn complete", root sessions only, 5 s cooldown |
| `api-session/error` | Chrome notification "Turn failed", message truncated to 160 chars |
| `approval/request` | Chrome notification "Approval needed"; `next()` passes through immediately |
| `user-questions/request` | Chrome notification "Question waiting"; `next()` passes through immediately |

- **Chrome first.** The plugin calls the Notification API. A granted permission and a secure
  context are the only prerequisites.
- **Silent toast fallback.** If the permission is denied/pending, the origin is not a secure
  context, the Notification API is unavailable, or the constructor/`onerror` fails, the event is
  shown as the **native DSH toast** and nothing else. There is no sound, no second notification
  channel, and no title-bar marker.
- **One tab delivers.** Multiple tabs elect a leader (Web Locks, localStorage lease fallback) so an
  event is not announced once per tab. A focused tab always delivers.
- **No sound engine.** The plugin never synthesizes audio, never ships or stores audio, and never
  uses `<audio>`/Web Audio/IndexedDB. When the OS notification has a sound, it is the **operating
  system's own** notification sound.

## 2. Windows and install-environment behavior

The Chrome notification parameters branch on the **runtime platform** and the **install mode**.
Platform detection order: DSH's `document.documentElement.dataset.platform` (the native shell sets
it; native code also tests it for `darwin`), then `navigator.userAgentData.platform`, then
`navigator.platform`, then `navigator.userAgent`. Install mode is `installed` when the page runs in
a standalone/minimal-ui/fullscreen display mode (or `navigator.standalone`), otherwise `browser`.

| Environment | `requireInteraction` | `silent` | `tag` |
|---|---|---|---|
| **Windows, installed app** | `true` for every kind — the Action Center keeps the alert while the app window is minimized, so a completion cannot be auto-dismissed | `false` (the OS plays the sound) | unique per event |
| **Windows, browser tab** | follows the "Keep approval alerts open" setting; approval/question only | `false` | unique per event |
| **macOS** | `false` — Chrome does not honour `requireInteraction`, so claiming it would misrepresent the behavior | `false` | unique per event |
| **Linux / other** | follows the setting; approval/question only | `false` | unique per event |

- **Why a unique tag on Windows:** Windows replaces an existing notification that reuses a `tag`,
  which silently drops repeated events. Every event gets a fresh tag so completions accumulate in
  the Action Center instead of being replaced.
- **Permission guidance is platform-specific:** a Windows profile points at Chrome's site settings
  and **Windows Settings → System → Notifications**; other platforms point at the browser's site
  settings. The guidance is shown next to the status row and is the only place a blocked
  permission is explained.
- Nothing else is Windows-specific: event filtering, cooldowns, tab leadership, locale and the
  toast fallback are generic.

## 3. Install

The package name stays `@nolit/dsh-notify-web`; only the **display identity** changed to
"Notify for Chrome" / "알림 for 크롬". Renaming the npm package would break the live profile's
`link:` dependency.

Local checkout (the live profile already links it):

```bash
dsh plugin --profile web add "link:/path/to/dsh-plugins/dsh-notify"
```

From npm after publishing:

```bash
dsh plugin --profile web add @nolit/dsh-notify-web
```

The package must be listed in the profile's `dsh.profile.bundles`. Reload the DSH page after
installing. If `lib/client.js` has a syntax error only this plugin is disabled; the DSH core keeps
working.

## 4. Settings

**Settings → Notify for Chrome** (English; the label is **알림 for 크롬** when the host locale is
Korean) renders native DSH settings surfaces only:

- a native `Tag` for the Chrome-notification status, native `Button` actions, native `Switch`
  toggles and a native `Input` for the cooldown;
- the section navigation icon is a **DSH icon** (`IconAlarmClockOutlineRegular`), registered through
  `settings.section.icon`; the plugin ships no icon set of its own;
- typography comes from the live DSH tokens `--dsh-content-font-size` /
  `--dsh-content-font-size-secondary` and their `--dsh-content-font-delta*` line-height deltas;
  colours and surfaces come from `--dsw-*` tokens. The plugin **injects no stylesheet**, sets **no
  font-family** and hardcodes **no pixel font size**.

Settings rows:

| Row | Default | Meaning |
|---|---|---|
| Turn complete / Approval needed / Question waiting / Turn error | on | which events notify |
| Include subagents | off | also notify for subagent complete/error |
| Hide completion alerts while focused | off | suppress completion while the DSH tab is focused |
| Keep approval alerts open | on | `requireInteraction` for approval/question where supported (Windows/Linux) |
| Completion cooldown | 5 s | per-session grouping window |

Preferences persist in the browser's `localStorage` under `dsh-notify-web:settings` (version 2).
They are browser preferences, not Host configuration: the plugin's Host half is intentionally a
no-op and exposes no settings namespace. No audio file is read, stored or referenced.

Guidance rules:

- **Permission pending** → the Enable button is shown.
- **Denied / insecure / unsupported** → the Enable button is **hidden** (a capability that is gone
  is not shown as a broken control); the row explains what to change, and the test action still
  exercises the toast fallback.

## 5. Localization

English is the default. Korean is used **only** while the host locale (`ctx.locale.active`) is
Korean; a locale change switches the next notification and the settings strings live.

- Source of truth: [`locale/en.json`](locale/en.json) and [`locale/ko.json`](locale/ko.json).
- `scripts/gen-locale.mjs` bakes them into `lib/locale-table.js`; `scripts/build-client.mjs` inlines
  that table into `lib/client.js` (the browser loader cannot import JSON).
- No hardcoded Korean exists outside the baked dictionary (a test enforces this).
- Display identity: English **Notify for Chrome**, Korean **알림 for 크롬**.

## 6. Limitations

- Notifications work **only while the DSH tab is open**. There is no service-worker push backend.
- The origin must be a **secure context** (HTTPS or `localhost`/`127.0.0.1`). Plain
  `http://<LAN-IP>:3080` cannot show OS notifications in Chrome; the toast fallback is used.
- Background-tab throttling, browser notification policy and OS Focus Assist / Do Not Disturb can
  change what is shown.
- Approval/question notifications do not replace the DSH approval UI; the event handler passes
  `next()` through immediately.

## 7. Privacy

- No `fetch`, `XMLHttpRequest`, `WebSocket`, `EventSource` or local port; no filesystem access.
- The only storage is the settings object in `localStorage` plus the tab-leader lease key.
- Notification bodies are fixed copy plus the session title (80 chars max); prompts, code and tool
  arguments are never included.
- Notification clicks only focus the DSH tab; no external link is opened.

## 8. Development

```bash
cd dsh-notify
npm test          # pretest runs gen-locale + build-client, then node --test
npm run build     # regenerate lib/locale-table.js and lib/client.js
node --check lib/client.js
node --check lib/index.js
```

Tests use mocked browser APIs (Notification, localStorage, Web Locks) and assert event filtering,
cooldowns, approval/question pass-through, the Chrome-vs-toast channel decision, Windows/macOS/Linux
parameter branches, locale switching, settings persistence, native-primitive rendering, the
typography token contract, and the absence of every removed legacy path.

## 9. Structure

- `lib/client.src.js` — editable browser-half source (baked by `scripts/build-client.mjs`).
- `lib/client.js` — shipped browser entry (generated; do not edit by hand).
- `lib/locale-table.js` — generated locale dictionary (from `locale/*.json`).
- `lib/index.js` — no-op Host half; registers the package only. No services, no I/O.
- `cordis.patch.yml` — bundle row and default settings.
- `market/index.json` — market/index entry (renamed titles, version, no audio keyword).

## 10. License and assets

- Code: MIT. See [LICENSE](LICENSE).
- The package bundles **no fonts, logos or audio**. The manifest icon is the neutral clock SVG at
  [`icon.svg`](icon.svg)/[`market/icons/dsh-notify.svg`](market/icons/dsh-notify.svg).
- The historical `docs/` and `prototype-windows/` trees are kept as history; neither is shipped in
  the package (`package.json` `files`) nor referenced by the notification code path.

---

## 한국어 요약

**알림 for 크롬**은 DeepSeek Harness의 턴 완료·도구 승인·질문·오류를 **크롬 알림**(Web
Notification API)으로 알립니다. 크롬이 알림을 막거나 표시할 수 없으면 **소리 없이 DSH 인앱
토스트**로 대신 알립니다. 자체 오디오 엔진·BYO 오디오·자체 CSS·네이티브 앱/포트/파일 경로는
모두 제거되었습니다.

- 설정은 **설정 → 알림 for 크롬**에서 하며, DSH 네이티브 컴포넌트(Switch/Button/Tag/Input/
  Toast)와 DSH 디자인·타이포그래피 토큰만 사용합니다.
- 영어가 기본이고, 호스트 로케일이 한국어일 때만 한국어로 표시됩니다.
- Windows에서는 플랫폼과 설치 환경(설치된 앱/브라우저 탭)에 따라 알림 파라미터가 달라집니다:
  설치된 앱은 모든 알림을 닫을 때까지 유지하고, 브라우저 탭은 승인·질문만 유지합니다.
  macOS에서는 `requireInteraction`을 사용하지 않습니다.
