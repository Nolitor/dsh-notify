# 2026-10-24 — Linux/Pop!_OS desktop verification of `@nolit/dsh-notify-web`

Target: DSH **0.2.1-rc.3** on Pop!_OS (Ubuntu-based), Node v24.2.0.
Method: static audit against the real rc.3 install + isolated `DSH_HOME=/tmp/dsh-home-B`
served on a spare port + headless Chromium (CDP) driving the real page.
Nothing under `~/.dsh` was modified; the live 3080 server was never restarted.

## 1. Verdict (short)

The plugin **boots and works** on this Linux box, but the advertised
"hybrid/dual mode" is **misleading for remote browsers**:

| Capability | Served on `localhost:3080` (secure) | Served on `http://<lan-ip>:3080` (insecure) |
|---|---|---|
| OS/desktop notification | ✅ works (permission grantable, `show` fires) | ❌ **impossible** — Chrome pins `permission` to `denied`, no prompt exists |
| In-page toast fallback | ✅ | ✅ (this is the only channel that works) |
| Synth chime (WebAudio) | ✅ | ✅ |
| Settings/consent UI | ✅ | ✅ |

So "dual mode" (OS notification **and** in-page) degrades to **toast-only** for any
browser that is not on the same machine. That is a real capability gap, not a bug
in the plugin — it is a platform constraint that the plugin previously hid.

## 2. Environment findings (measured, not assumed)

| Item | Measured value | Note |
|---|---|---|
| Session type | **No graphical user session.** `XDG_SESSION_TYPE`, `WAYLAND_DISPLAY`, `DISPLAY` all unset in this context | DSH runs as a **user** systemd unit |
| `loginctl` sessions | only `cosmic-greeter` on `seat0/tty1` (uid 987) | The user (uid 1000) has no seated graphical session |
| `dsh-web.service` | `systemctl --user` → `active`; listening `0.0.0.0:3080` | User scope, **not** system scope |
| D-Bus session bus | `unix:path=/run/user/1000/bus` present | bus reachable |
| `org.freedesktop.Notifications` | **`ServiceUnknown: The name is not activatable`** | No notification daemon is running **or** activatable |
| Daemon on the bus | none (only `com.system76.CosmicStatusNotifierWatcher`, an SNI tray watcher) | Not a notification server |
| `notify-send` | **not installed** (`libnotify-bin` absent) | `libnotify4` is installed (library only) |
| `notification-daemon` | installed (`/usr/lib/notification-daemon/notification-daemon`, 3.20.0) but has **no D-Bus service file** | Never auto-activated |
| dunst / mako / notify-osd / xfce4-notifyd | all absent | — |

**Consequence:** no process on this machine could display a freedesktop
notification today. A browser notification would be handed to the OS and
**silently dropped**. The in-page toast is the only reliable channel here.

## 3. Defects found

| # | Severity | Defect | Status |
|---|---|---|---|
| D1 | **High** | `dsh.client.inject` listed `@deepseek-ai/dsh-client-ui-slots`, which **does not exist** in rc.3. The `slots` service is owned by `@deepseek-ai/dsh-client-ui-renderer` (`super(ctx,"slots")`), injected by 31 core plugins. | **FIXED** |
| D2 | **Medium** | No secure-context awareness. On `http://<lan-ip>:3080` the API reports `denied`, so the UI claimed "알림 차단됨" (user blocked) when the truth is "never possible". | **FIXED** |
| D3 | Low | No desktop notification daemon on this host (environment, not plugin). | Reported — see §2 |
| D4 | Low (advisory) | `approval/request` + `user-questions/request` listeners are bound as `(scope, request, next)`; rc.3 core consumers use `(request, next)`. Verified harmless today (rc.3 always supplies the `next` bail closure) but the leading `scope` arg is a dead parameter. | Documented, **not changed** |

### D1 detail — why it still booted

`client-modules` resolves each `inject` entry against the boot graph and
**silently skips** unknown ids:

```js
for (const packageName of row.inject) {
  const dependency = this.graphRows.get(packageName);
  if (dependency !== void 0) await this.arriveDependency(row.id, dependency, [], visited);
}
```

So the package booted anyway (verified: `window.__dshNotifyWeb` exists, both slots
rendered, zero console errors) but it lost its **ordering guarantee** after the
renderer that declares the slot map. It worked by luck.

### D2 detail — measured evidence

Same CDP grant (`Browser.grantPermissions`, `notifications`) applied to both
origins, full Chromium in new-headless mode:

```
http://192.168.50.203:3098  isSecureContext=false  permission=denied  requestPermission→denied  (no prompt)
http://localhost:3098       isSecureContext=true   permission=granted requestPermission→granted  events=["show"]
```

The insecure origin is forced to `denied` **even with a pre-granted permission**.

## 4. What was verified working

- `node --test test/client.test.mjs` → **19/19 pass** (15 original + 4 new).
- Boot on isolated server: no exceptions, no console errors, both slots render
  (`settings.section` nav + `shell.overlay` consent card "DSH 알림을 켜시겠습니까?").
- Event wiring uses live rc.3 APIs: `ctx.remote.$on('api-session/status'|'api-session/error'|'approval/request'|'user-questions/request')`
  (all four are declared in `dsh-api-remotes`' forwarded-event allowlist) and
  `ctx.sessions.list.getSnapshot().byId` + `ctx.sessions.scopeOf(ctx)` (both real).
- `exports.inject = ['remote','sessions','slots','locale']` — all four are real
  rc.3 client services.
- Audio: WebAudio reaches `running`, oscillators schedule, `<audio>` data-URI
  fallback plays; no throw in headless, no gesture requirement violated.
- Degradation: on insecure origin the plugin now reports `insecure` and falls
  back to a toast (verified on a real LAN origin through a TCP proxy).

## 5. Verification commands

```bash
cd /home/minami/Workspace/projects/dsh-workspace/dsh-plugins/dsh-notify
node --test test/client.test.mjs

# injected package names
ls /home/minami/.local/nodejs/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/ | grep -E 'ui-slots|ui-renderer'

# desktop notification pipeline
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
gdbus call --session --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.GetServerInformation

# isolated boot (spare port, killed afterwards)
rsync -a ~/.dsh/ /tmp/dsh-home-B/
ln -sfn "$PWD" /tmp/dsh-home-B/profiles/web/node_modules/@nolit/dsh-notify-web
DSH_HOME=/tmp/dsh-home-B ~/.local/bin/dsh --profile web \
  --patch /tmp/dsh-home-B/profiles/web/cordis.patch.yml.append.yml \
  --host 127.0.0.1 --port 3098 --no-open
```

## 6. Recommendation

1. Enable the plugin. In-page toast + chime is genuinely useful on this host.
2. Do **not** market it as desktop notifications unless DSH is reached via
   `https://` or `localhost`. For a real desktop channel, install a notification
   daemon (`sudo apt install libnotify-bin` for `notify-send`; and enable a
   daemon such as `dunst` or run a COSMIC session) — otherwise the OS drop is silent.
3. Long term: an HTTPS reverse proxy (or SSH port-forward to `localhost:3080`)
   restores full OS notifications for remote browsers.
