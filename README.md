# Notify for Chrome

<!-- skeleton:
version: 2.0
kind: readme
status: active
updated: 2026-11-05
summary: Operator manual and behavior contract for Notify for Chrome (Korean: 알림 for 크롬) — Chrome/Web Notification only, silent in-app toast fallback, native DSH settings rows and typography, Windows/install-mode notification branches.
-->

> Status: active · Updated: 2026-11-06 · Package: `@nolit/dsh-notify` v`0.0.1-rc.3` · Korean display name: **알림 for 크롬** · Parent: `README.md` in the `dsh-plugins` workspace

**Notify for Chrome** turns DeepSeek Harness events into **Chrome notifications** (the Web
Notification API, `new Notification(...)`). It has no native app, no ports, no IPC, no file queue
and no system notifier. When Chrome cannot show a notification, the plugin falls back to a
**silent in-app toast**.

## 0. Version numbering — why `0.0.1-rc.3` is not lower than `0.2.1`

The version number went **down** against this project's own history, on purpose. Two separate
facts explain it, and until 2026-11-06 neither was written down anywhere.

**`0.2.x` was never this plugin's version.** The `v0.2.0` and `v0.2.1` releases belonged to the
**Windows PowerShell/WPF prototype** (a tray widget polling the DeepSeek billing window). The
browser plugin lived inside that repository under `plugin/` and happened to carry the same
number — by accident, not by design.

**The `@nolit` ladder was reset by owner decision on 2026-11-05.** Every `@nolit` package moved
to one scheme, `0.0.1-rc.N`, in which only the `rc#` moves. `0.1.8` and `0.2.1` are not
milestones under that scheme; the scheme replaced them.

| Surface | Before | After |
| :--- | :--- | :--- |
| Version scheme | per-track, drifting (`0.1.6 → 0.1.7 → 0.1.8 → 0.2.1`) | **`0.0.1-rc.N`** |
| Package | `@nolit/dsh-notify-web` @ `0.2.1`, nested in `plugin/` | **`@nolit/dsh-notify`** @ `0.0.1-rc.3`, repository root |
| Repository | Windows prototype at root | plugin at root, prototype preserved in `prototype-windows/` |

The `-web` suffix came from the 2026-10-24 recovery and was never the owner's choice;
`PROVENANCE.md` documented the package as `@nolit/dsh-notify` the entire time while the files
said `-web`. The rename is part of `0.0.1-rc.3`.

Version numbers are the owner's decision. An agent must not choose, bump or "stabilise" one.

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

**Which OS does the environment card report?** The **browser's** OS — the machine running the tab
that shows the notification — not the OS running the `dsh` host process. The two are independent:
a Windows Chrome can be pointed at a DSH server on Linux (the default remote setup), and the
notification rules that matter (Action Center persistence, `requireInteraction` support, the
installed-app branch) are properties of the browser's OS.

The sensitivity is per-platform, measured:

| Browser OS | Installed app | Behaviour |
|---|---|---|
| Windows | yes | `requireInteraction: true` for every kind; the app window and Action Center keep them |
| Windows | no | `requireInteraction` follows the setting, approval/question only |
| Linux | either | same as the Windows browser tab |
| macOS | either | `requireInteraction` is not honoured by Chrome, so it stays `false` |
| Android / other | either | `silent: false`, unique `tag`; no persistence |

Because a value like "Windows" next to a Linux host looks wrong, the row is labelled
**Browser OS** (브라우저 OS) and carries that explanation inline.

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

The package name stays `@nolit/dsh-notify`; only the **display identity** changed to
"Notify for Chrome" / "알림 for 크롬". Renaming the npm package would break the live profile's
`link:` dependency.

Local checkout (the live profile already links it):

```bash
dsh plugin --profile web add "link:/path/to/dsh-plugins/dsh-notify"
```

From npm after publishing:

```bash
dsh plugin --profile web add @nolit/dsh-notify
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

The page is grouped into four cards. The two owner-requested categories (2026-11-06) are the
**DeepSeek peak timer** and **notifications**, in that order.

**알림 조건 (notification rows)**

| Row | Default | Meaning |
|---|---|---|
| Turn complete / Approval needed / Question waiting / Turn error | on | which events notify |
| Include subagents | off | also notify for subagent complete/error |
| Hide completion alerts while focused | off | suppress completion while the DSH tab is focused |
| Keep approval alerts open | on | `requireInteraction` for approval/question where supported (Windows/Linux) |
| Completion cooldown | 5 s | per-session grouping window |

**딥시크 피크 타이머 (peak timer rows)**

| Row | Default | Meaning |
|---|---|---|
| Show peak countdown chip | on | 7-segment `HH:MM:SS` chip in the Session header: green off-peak, red at peak |
| Announce peak changes | on | Chrome notification + `setAppBadge` when the billing window flips |
| Show timer on other providers | **off** | also render the chip when the active route is *not* an official DeepSeek route |

### The peak timer only trusts official DeepSeek routes by default

The peak/off-peak clock is a property of **DeepSeek's own API billing**
([pricing footnote](https://api-docs.deepseek.com/quick_start/pricing)). DeepSeek publishes the
off-peak discount for its own API; **a different service serving the same model may bill
differently**, so the timer is a *reference*, not a fact, on any other route.

The plugin therefore gates on the **provider id**, never on a model name:

| Route | Chip by default |
|---|---|
| `deepseek-official` (official API-key route) | shown |
| `deepseek-account` (official account route) | shown |
| everything else (OpenCode, DeepInfra, Antigravity, any proxy/gateway) | **hidden** |

Those two ids are the ones the official DSH packages register. **Provider ids differ between
installations** — if your setup exposes the official DeepSeek route under a different id, turn on
**Show timer on other providers** and the chip appears on every route. The default stays
conservative because a wrong "50% off" claim is worse than a hidden widget.

The live selection is read from `[data-provider-id][data-model-id]` on the model selector trigger,
which is the same path DeepInfra's cost chip uses. Nothing is guessed from the model name.

The settings card carries the caveat inline, in the owner's wording (2026-11-06):

> 딥시크는 공식 모델 API에 대해서만 할인을 명시합니다. 같은 모델이라도 다른 제공자는 서비스 요금이
> 다를 수 있으며 보장하지 않습니다. 그 경우 이 타이머는 참고 사항일 뿐입니다.
>
> *DeepSeek states this discount only for its official model API. A different provider may charge
> differently for the same model, and that is not guaranteed. In that case this timer is a reference
> only.*

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

### Browser support — Chrome / Chromium required

The plugin is built for **Chrome and Chromium-based browsers** (Edge, Brave, Opera, Vivaldi, Arc).
Those are the engines where the whole surface below exists at once. **On any other browser, correct
operation is not guaranteed and is not tested.**

| Capability | Chrome / Chromium | Firefox | Safari |
|---|---|---|---|
| `new Notification()` | yes | yes | 16+ only |
| `badge` / `setAppBadge` | 81+ | no (falls back silently) | no |
| `navigator.locks` (tab leader) | 69+ | yes | no (localStorage lease fallback) |
| `requireInteraction` | Windows/Linux | **ignored** | **ignored** |
| Installed-app notification branch | yes | n/a | n/a |

**The plugin does not detect the browser.** It feature-detects (`Notification`, `isSecureContext`,
`navigator.locks`, `setAppBadge`) and degrades, but it never claims a browser is supported just
because it is not Chrome. A non-Chromium browser may look functional while behaving differently —
for example Firefox accepts `requireInteraction` and ignores it, so an approval alert auto-dismisses
even though the setting is on.

Recommended minimum: **Chrome 81+** (when `setAppBadge` landed; everything else the plugin uses is
older). Older Chrome still works, minus the badge channel.

### Security constraints that can stop a notification appearing

These are browser/OS security rules, not plugin bugs. Each one degrades to the **silent in-app
toast** rather than failing loudly, which is why the toast fallback exists.

| Constraint | What the user sees | Measured behaviour |
|---|---|---|
| **Permission not granted** (`default`) | nothing from the OS | `new Notification(...)` **does not throw** — it looks successful and shows nothing. The plugin checks `Notification.permission === 'granted'` *before* constructing, so it routes to the toast instead. |
| **Permission blocked** (`denied`) | nothing, and no prompt returns | `requestPermission()` resolves `'denied'` immediately; Chrome will not prompt again for the origin. Only the user can undo it in site settings. The plugin hides the Enable button, because a control that cannot work is not shown as a broken one. |
| **Insecure origin** | nothing | `http://<LAN-IP>:3080` is not a secure context; Chrome refuses OS notifications. Use `https://` or `localhost`. Reported as `insecure`. A self-signed certificate needs to be trusted once in the browser; do **not** browse with certificate errors bypassed — notifications and the peak timer need a genuinely secure context. |
| **No user gesture** | prompt never appears | `requestPermission()` needs a click. A call on page load is auto-denied; the plugin drives it from the Enable button only. |
| **OS Do Not Disturb** / Focus Assist | nothing, or a silent banner | The OS owns this; the page cannot override it and cannot detect it. |
| **Browser-level site mute** | nothing | Silent skip at the Chrome layer; indistinguishable from a delivered notification. |
| **Tab closed** | nothing | No service-worker backend, so no delivery once the DSH tab is gone. |

- Notifications work **only while the DSH tab is open**. There is no service-worker push backend.
- Background-tab throttling, browser notification policy and OS Focus Assist / Do Not Disturb can
  change what is shown.
- Approval/question notifications do not replace the DSH approval UI; the event handler passes
  `next()` through immediately.

## 7. Privacy

- No `XMLHttpRequest`, `WebSocket`, `EventSource` or local port; no filesystem access.
- **One network request**: the peak timer fetches the Chinese public-holiday list from
  `raw.githubusercontent.com/NateScarlet/holiday-cn`. Nothing is sent but the request itself — no
  prompt, code, session title, token or identifier. The response is cached in `localStorage` for 10
  days. Disable **Show peak countdown chip** and the request never happens.
- The only storage is the settings object, the tab-leader lease key and that holiday cache, all in
  `localStorage`.
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

**버전이 내려간 이유부터**: `0.0.1-rc.3`은 `0.2.1`보다 낮은 것이 아닙니다. `0.2.x`는 이
플러그인의 버전이 아니라 같은 저장소에 있던 **Windows 프로토타입**의 버전이었고, 2026-11-05
소유자 결정으로 모든 `@nolit` 패키지가 **`0.0.1-rc.N`** 단일 사다리로 재설정됐습니다.
`rc#`만 올라갑니다. 패키지명도 `@nolit/dsh-notify-web` → **`@nolit/dsh-notify`** 로
바뀌었습니다. `-web`은 2026-10-24 복구 당시 붙은 것으로 소유자가 고른 이름이 아니었습니다.

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
