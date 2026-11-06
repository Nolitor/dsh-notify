/**
 * Notify for Chrome — browser half.
 *
 * ONE notification channel: the Chrome / Web Notification API
 * (`new Notification(...)`). There is no sound engine, no BYO audio, no
 * IndexedDB audio store and no self-authored stylesheet.
 *
 * Layers:
 *   1. createNotifyCore(): headless engine. Event filtering, cooldowns,
 *      permission state, tab leadership, platform/install-environment detection,
 *      the Chrome-notification parameters, and the silent in-app toast fallback
 *      record. No React, no slots, no rendering.
 *   2. UI adapters: `settings.section` (native DSH primitives and tokens) and
 *      `shell.overlay` (the native DSH Toast shown only when Chrome cannot show
 *      the notification).
 *
 * Fallback contract (owner decision 2026-11-05): Chrome notification first; if
 * permission is denied/unavailable, the origin is not a secure context, or the
 * Notification constructor/onerror fails, show the DSH toast silently. The toast
 * is a fallback UI, never a second notification channel.
 *
 * Windows note: Chrome notification parameters branch on the runtime platform
 * and the install mode (installed app vs browser tab). See notificationOptions().
 *
 * Locale: English is the default; Korean is used only while the host locale is
 * Korean. Strings live in locale/en.json + locale/ko.json and are baked into
 * this file by scripts/gen-locale.mjs + scripts/build-client.mjs.
 */
window.__ModuleLoader__.load({
  id: '@nolit/dsh-notify-web',
  factory: (require) => {
    const React = require('react')
    const primitives = require('@deepseek-ai/dsh-client-ui-primitives')
    const Button = primitives.Button
    const Input = primitives.Input
    const Switch = primitives.Switch
    const Tag = primitives.Tag
    const Toast = primitives.Toast

    const exports = {}

    // Baked from locale/*.json by scripts/build-client.mjs.
    const I18N = __NOTIFY_I18N__

    const SETTINGS_KEY = 'dsh-notify-web:settings'
    const LEADER_KEY = 'dsh-notify-web:leader'
    const LEADER_LOCK = 'dsh-notify-web:leader-lock'
    const MAX_TITLE = 80
    const MAX_ERROR = 160
    const REQUEST_TTL = 30000
    const TOAST_HOLD_MS = 6000
    const SECTION_ID = 'notifications'
    const PEAK_CHIP_ID = 'dsh-notify-web.peak'
    // Only the official DeepSeek routes bill on the peak/off-peak clock. The
    // peak windows are a property of DeepSeek's own API billing; a third-party
    // reseller or gateway (OpenCode, DeepInfra, Antigravity, any OpenAI-shaped
    // proxy) has its own price sheet, so showing the chip there would state a
    // price the user is not paying.
    //
    // The ids are the ones the official packages actually register (measured
    // 2026-11-06): `dsh-llm-deepseek-api-key` -> "deepseek-official" and
    // `dsh-llm-deepseek-account` -> "deepseek-account".
    const OFFICIAL_DEEPSEEK_PROVIDER_IDS = Object.freeze(['deepseek-official', 'deepseek-account'])
    // The model selector stamps the live selection on the trigger element.
    // Measured in dsh-client-ui-model-selection (renderModelLabel, placement
    // "trigger"): a `[data-provider-id][data-model-id]` node inside the
    // composer. This is the same read path DeepInfra's cost chip uses.
    const PROVIDER_PROBE = '[data-provider-id][data-model-id]'
    const PEAK_HOLIDAY_URL = 'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json'
    const PEAK_HOLIDAY_TTL_HOURS = 240
    const PEAK_HOLIDAY_TTL_UNPUBLISHED_HOURS = 24
    const PEAK_HOLIDAY_TIMEOUT_MS = 10000
    const PEAK_TICK_MS = 1000
    // Peak windows are a fixed UTC definition: 01:00-04:00 and 06:00-10:00,
    // Monday-Friday, excluding Chinese public holidays (api-docs.deepseek.com
    // /quick_start/pricing footnote 2). Off-peak is therefore half price.
    const PEAK_WINDOWS_UTC = [
      [1, 4],
      [6, 10],
    ]

    const DEFAULT_SETTINGS = Object.freeze({
      notifyOnComplete: true,
      notifyOnApproval: true,
      notifyOnQuestion: true,
      notifyOnError: true,
      completeCooldownMs: 5000,
      suppressWhenFocused: false,
      requireInteractionForApproval: true,
      notifyOnSubagents: false,
      showPeakChip: true,
      notifyOnPeakChange: true,
      // Off by default: the peak clock is DeepSeek's own billing. Another
      // provider serving the same weights has its own price sheet, so showing
      // the countdown there asserts a price the user is not paying.
      peakOnAnyProvider: false,
    })
    const SETTING_KEYS = Object.keys(DEFAULT_SETTINGS)

    function safe(fn, fallback) {
      try {
        return fn()
      } catch {
        return fallback
      }
    }

    function clamp(value, min, max) {
      const number = Number(value)
      if (!Number.isFinite(number)) return min
      return Math.min(max, Math.max(min, number))
    }

    function sanitizeText(value, max) {
      return String(value ?? '')
        .replace(/[\u0000-\u001f\u007f]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, max)
    }

    function randomId() {
      const crypto = globalThis.crypto
      if (crypto && typeof crypto.randomUUID === 'function') return crypto.randomUUID()
      return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
    }

    function createStore(initial) {
      let value = initial
      const listeners = new Set()
      return {
        get() {
          return value
        },
        set(next) {
          value = next
          for (const listener of [...listeners]) safe(() => listener(value))
        },
        subscribe(listener) {
          listeners.add(listener)
          return () => listeners.delete(listener)
        },
      }
    }

    function normalizeLang(value) {
      return String(value ?? '').toLowerCase().startsWith('ko') ? 'ko' : 'en'
    }

    function translate(lang, key, vars) {
      const table = I18N[lang] ?? I18N.en
      const value = table?.[key] ?? I18N.en[key] ?? key
      if (!vars) return value
      return String(value).replace(/\{(\w+)\}/g, (match, name) => String(vars[name] ?? ''))
    }

    function normalizeSettings(raw) {
      const source = raw && typeof raw === 'object' ? raw : {}
      const out = {}
      for (const key of SETTING_KEYS) {
        if (typeof DEFAULT_SETTINGS[key] === 'boolean') {
          out[key] = typeof source[key] === 'boolean' ? source[key] : DEFAULT_SETTINGS[key]
        }
      }
      out.completeCooldownMs = Number.isFinite(Number(source.completeCooldownMs))
        ? Math.round(clamp(source.completeCooldownMs, 0, 60000))
        : DEFAULT_SETTINGS.completeCooldownMs
      return out
    }

    // ------------------------------------------------------------------
    // Runtime environment (platform + install mode)
    // ------------------------------------------------------------------

    /**
     * Resolve the runtime platform. DSH's native shell writes
     * `documentElement.dataset.platform` (measured: native code tests it for
     * "darwin"); a browser does not, so fall back to userAgentData / platform /
     * userAgent. Any of these may be absent in a test or a hardened browser.
     */
    function detectPlatform(source) {
      const doc = source?.document
      const nav = source?.navigator
      const dataset = safe(() => doc?.documentElement?.dataset?.platform, '')
      const uaData = safe(() => nav?.userAgentData?.platform, '')
      const platform = safe(() => nav?.platform, '')
      const userAgent = safe(() => nav?.userAgent, '')
      const probe = [dataset, uaData, platform, userAgent].filter(Boolean).join(' ').toLowerCase()
      // Check Apple names first: "darwin" contains the substring "win", so a
      // Windows-first check would classify every macOS browser as Windows.
      if (/mac|darwin|iphone|ipad/.test(probe)) return 'macos'
      if (/win/.test(probe)) return 'windows'
      if (/android/.test(probe)) return 'android'
      if (/linux|x11|cros/.test(probe)) return 'linux'
      return 'other'
    }

    /**
     * Identify the rendering engine family.
     *
     * The plugin targets Chrome and Chromium only, but it must not *claim* a
     * browser is supported merely because it is not Chrome. Firefox and Safari
     * expose `Notification` and then behave differently (they ignore
     * `requireInteraction`, they have no `setAppBadge`), so the UI says which
     * engine it found instead of implying everything works.
     *
     * @param source - `{ navigator }` from the host page.
     * @returns `'chromium' | 'firefox' | 'safari' | 'other'`.
     */
    function detectBrowser(source) {
      const nav = source?.navigator
      const ua = safe(() => nav?.userAgent, '') || ''
      const vendor = safe(() => nav?.vendor, '') || ''
      // Chromium: every Chromium browser identifies as Chrome/ (Edge adds
      // Edg/, Opera OPR/, Brave navigator.brave). Check it first because the
      // others are all Chromium derivatives and would match their own tokens.
      const isChromium =
        /Chrome\/|Chromium\//.test(ua) ||
        /Google Inc\.|Microsoft Edge|Opera|Brave/i.test(vendor) ||
        safe(() => nav?.userAgentData?.brands?.some?.((b) => /Chromium|Google Chrome|Microsoft Edge|Opera|Brave/i.test(b?.brand ?? '')), false) === true
      if (isChromium) return 'chromium'
      if (/Firefox\//.test(ua)) return 'firefox'
      if (/Safari\//.test(ua) && /Apple/.test(vendor)) return 'safari'
      return 'other'
    }

    /**
     * Resolve the install mode: an installed/standalone app vs an ordinary
     * browser tab. Windows Chrome behaves differently in the installed case
     * because notifications are owned by the app window and the Windows Action
     * Center, so the parameters are chosen per mode (see notificationOptions).
     */
    function detectInstallState(source) {
      const nav = source?.navigator
      const matchMedia = source?.matchMedia
      if (safe(() => nav?.standalone === true, false)) return 'installed'
      for (const query of ['(display-mode: standalone)', '(display-mode: minimal-ui)', '(display-mode: fullscreen)']) {
        if (safe(() => matchMedia?.(query)?.matches === true, false)) return 'installed'
      }
      return 'browser'
    }

    function detectEnvironment(source) {
      return Object.freeze({
        platform: detectPlatform(source || {}),
        installState: detectInstallState(source || {}),
        browser: detectBrowser(source || {}),
      })
    }

    /**
     * Chrome-notification parameters for an event, platform and install mode.
     *
     * MEASURED / DOCUMENTED BRANCHES:
     *   - Every platform: `silent: false`. Notify for Chrome never synthesizes
     *     audio; the operating system's own notification sound is the only
     *     sound. Chrome on Windows ignores `silent` and plays the OS sound
     *     regardless; on macOS/Linux `false` is the default.
     *   - Every platform: a unique `tag`. Windows replaces an existing
     *     notification that reuses a tag, which silently dropped repeated events
     *     (measured in the Windows prototype); a unique tag keeps each event in
     *     the Action Center / notification list.
     *   - Windows + installed app (`display-mode: standalone`): the app window
     *     owns the notifications and the Action Center keeps them while the
     *     window is minimized, so `requireInteraction: true` for every kind — a
     *     completion cannot be missed by auto-dismiss.
     *   - Windows/Linux browser tab: `requireInteraction` follows the user
     *     setting and only applies to approval/question.
     *   - macOS: `requireInteraction` is not honoured by Chrome, so it is false
     *     even when the setting is on (a truthy unsupported option would
     *     misrepresent the behaviour).
     */
    function notificationOptionsFor(kind, settings, environment, nowFn, idFn) {
      const windowsInstalled =
        environment?.platform === 'windows' && environment?.installState === 'installed'
      const supportsRequireInteraction =
        environment?.platform === 'windows' || environment?.platform === 'linux'
      const persistentBySetting =
        !!settings?.requireInteractionForApproval && (kind === 'approval' || kind === 'question')
      return {
        tag: `dsh-notify:${kind}:${nowFn ? nowFn() : Date.now()}:${idFn ? idFn() : randomId()}`,
        silent: false,
        requireInteraction: windowsInstalled ? true : supportsRequireInteraction && persistentBySetting,
      }
    }

    // ------------------------------------------------------------------
    // DeepSeek peak / off-peak engine
    //
    // Pure decision logic, ported from the measured Windows prototype
    // (prototype-windows/providers/deepseek-peak.ps1). Peak windows are a fixed
    // UTC definition; Chinese public holidays come from holiday-cn and are
    // matched on the Beijing calendar day (UTC+8), because the published dates
    // are State Council local dates.
    //
    // Owner decision 2026-11-06: makeup workdays (调休, `isOffDay: false`) bill
    // as OFF-PEAK. The official footnote says weekends are off-peak "in full",
    // so a Saturday/Sunday makeup day stays off-peak. There is no
    // treatMakeupAsPeak flag any more; the divergence is resolved.
    // ------------------------------------------------------------------

    function beijingDateKey(utcMs) {
      return new Date(utcMs + 8 * 3600 * 1000).toISOString().slice(0, 10)
    }

    function beijingYear(utcMs) {
      return new Date(utcMs + 8 * 3600 * 1000).getUTCFullYear()
    }

    function peakHolidayIndex(holidayData) {
      // Returns a Map of YYYY-MM-DD -> isOffDay, or null when the payload is
      // unusable. Unpublished years (empty `papers`) are treated as no data.
      if (!holidayData || typeof holidayData !== 'object') return null
      if (!Array.isArray(holidayData.days)) return null
      const papers = Array.isArray(holidayData.papers) ? holidayData.papers : []
      if (papers.length === 0) return null
      const index = new Map()
      for (const day of holidayData.days) {
        if (!day || typeof day.date !== 'string') continue
        index.set(day.date, day.isOffDay === true)
      }
      return index.size > 0 ? index : null
    }

    function peakDecision(utcMs, holidayData) {
      const utc = new Date(utcMs)
      const index = peakHolidayIndex(holidayData)
      const confidence = index ? 'exact' : 'estimated'

      if (index) {
        const key = beijingDateKey(utcMs)
        if (index.has(key)) {
          return index.get(key)
            ? { isPeak: false, reason: 'holiday', confidence: 'exact' }
            : { isPeak: false, reason: 'makeup-workday', confidence: 'exact' }
        }
      }

      const weekday = utc.getUTCDay()
      if (weekday === 0 || weekday === 6) {
        return { isPeak: false, reason: 'weekend', confidence }
      }

      const hour = utc.getUTCHours()
      for (const [from, to] of PEAK_WINDOWS_UTC) {
        if (hour >= from && hour < to) {
          return { isPeak: true, reason: 'weekday-peak', confidence }
        }
      }
      return { isPeak: false, reason: 'weekday-offpeak', confidence }
    }

    function peakNextChange(utcMs, holidayData, maxDays = 8) {
      // Minute scan: the boundary can only ever fall on a minute, and an 8-day
      // ceiling covers the longest holiday run.
      const current = peakDecision(utcMs, holidayData).isPeak
      let cursor = Math.floor(utcMs / 60000) * 60000 + 60000
      const limit = maxDays * 1440
      for (let i = 0; i < limit; i++) {
        if (peakDecision(cursor, holidayData).isPeak !== current) return cursor
        cursor += 60000
      }
      return null
    }

    function peakRemainingParts(nextChangeAt, nowMs) {
      if (!nextChangeAt) return { hours: 0, minutes: 0, seconds: 0, total: 0 }
      const total = Math.max(0, Math.floor((nextChangeAt - nowMs) / 1000))
      return {
        hours: Math.floor(total / 3600),
        minutes: Math.floor((total % 3600) / 60),
        seconds: total % 60,
        total,
      }
    }

    function pad2(value) {
      return String(value).padStart(2, '0')
    }

    function peakTimerText(nextChangeAt, nowMs) {
      const parts = peakRemainingParts(nextChangeAt, nowMs)
      // Hours keep growing past 99 for a long weekend; never truncate the number.
      return `${pad2(parts.hours)}:${pad2(parts.minutes)}:${pad2(parts.seconds)}`
    }

    function peakIsUnpublished(holidayData) {
      if (!holidayData || typeof holidayData !== 'object') return false
      const papers = Array.isArray(holidayData.papers) ? holidayData.papers : []
      return papers.length === 0
    }

    // ------------------------------------------------------------------
    // 7-segment glyph geometry
    //
    // Traced from the owner's design image: the digits sit in a 10x18 unit box
    // with the middle bar on the centre line, round caps, and a ~1.9 unit
    // stroke. Only the digits and the colon are needed for HH:MM:SS.
    // ------------------------------------------------------------------

    const SEVEN_SEGMENT_MAP = Object.freeze({
      0: ['a', 'b', 'c', 'd', 'e', 'f'],
      1: ['b', 'c'],
      2: ['a', 'b', 'g', 'e', 'd'],
      3: ['a', 'b', 'g', 'c', 'd'],
      4: ['f', 'g', 'b', 'c'],
      5: ['a', 'f', 'g', 'c', 'd'],
      6: ['a', 'f', 'g', 'e', 'c', 'd'],
      7: ['a', 'b', 'c'],
      8: ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
      9: ['a', 'b', 'c', 'd', 'f', 'g'],
    })

    // Segment endpoints in the 10x18 unit box (x, y) pairs.
    const SEVEN_SEGMENT_POINTS = Object.freeze({
      a: [1.4, 0.9, 8.6, 0.9],
      b: [9.1, 1.6, 9.1, 8.4],
      c: [9.1, 9.6, 9.1, 16.4],
      d: [1.4, 17.1, 8.6, 17.1],
      e: [0.9, 9.6, 0.9, 16.4],
      f: [0.9, 1.6, 0.9, 8.4],
      g: [1.4, 9.0, 8.6, 9.0],
    })

    function sevenSegmentLit(char) {
      return SEVEN_SEGMENT_MAP[char] ?? []
    }

    // ------------------------------------------------------------------
    // Headless core
    // ------------------------------------------------------------------

    function createNotifyCore(options = {}) {
      const config = options.config || {}
      const env = options.env || {}
      const sources = options.sources || {}
      const logger = env.logger || console

      const storage = env.storage
      const NotificationCtor = env.Notification
      const win = env.window
      const doc = env.document
      const nav = env.navigator
      const locks = env.locks
      const locale = env.locale
      const now = env.now || (() => Date.now())
      const setTimeoutFn = env.setTimeout || setTimeout
      const clearTimeoutFn = env.clearTimeout || clearTimeout
      const setIntervalFn = env.setInterval || setInterval
      const clearIntervalFn = env.clearInterval || clearInterval
      // Holiday data is fetched from the browser. The DSH page is a secure
      // context and raw.githubusercontent.com answers `access-control-allow-
      // origin: *` (measured 2026-11-06), so a plain cross-origin GET works.
      const fetchFn = env.fetch || (typeof globalThis.fetch === 'function' ? globalThis.fetch.bind(globalThis) : undefined)

      const environment = detectEnvironment({ document: doc, navigator: nav, matchMedia: env.matchMedia })

      const cooldowns = new Map()
      const recentRequests = new Map()
      let autoPermissionRequested = false
      let started = false
      let disposers = []
      let localeDispose = null

      function readJson(key, fallback) {
        return safe(() => {
          const raw = storage?.getItem(key)
          return raw ? JSON.parse(raw) : fallback
        }, fallback)
      }

      function writeJson(key, value) {
        safe(() => storage?.setItem(key, JSON.stringify(value)))
      }

      function loadSettings() {
        const stored = readJson(SETTINGS_KEY, {})
        return normalizeSettings({ ...DEFAULT_SETTINGS, ...(config || {}), ...(stored?.settings || stored || {}) })
      }

      function saveSettings(settings) {
        writeJson(SETTINGS_KEY, { version: 2, settings })
      }

      // A Notification is gated on a secure context. Plain HTTP on a LAN
      // address is not secure (only localhost/127.0.0.1 and HTTPS are), so a DSH
      // server reached as http://<lan-ip>:3080 can never show an OS notification:
      // Chrome reports permission === 'denied' with no prompt and no way to grant.
      function secureContextOf() {
        return safe(() => globalThis.isSecureContext !== false, true)
      }

      function permissionOf() {
        if (!NotificationCtor) return 'unsupported'
        const reported = NotificationCtor.permission || 'default'
        if (reported === 'denied' && !secureContextOf()) return 'insecure'
        return reported
      }

      function currentLang() {
        return normalizeLang(safe(() => locale?.active?.(), ''))
      }

      const stateStore = createStore({
        settings: loadSettings(),
        permission: permissionOf(),
        secureContext: secureContextOf(),
        leader: false,
        lang: currentLang(),
        environment,
        fallbackToast: null,
        lastEventAt: 0,
        lastDelivery: null,
        lastStatusEvent: null,
        peak: {
          isPeak: false,
          reason: 'weekday-offpeak',
          confidence: 'estimated',
          nextChangeAt: null,
          holidayYear: null,
          unpublished: false,
          loaded: false,
          view: 'timer',
        },
      })

      const getState = () => stateStore.get()
      const subscribe = (listener) => stateStore.subscribe(listener)

      function update(patch) {
        stateStore.set({ ...stateStore.get(), ...patch })
      }

      function updateSettings(next) {
        const settings = normalizeSettings(next)
        saveSettings(settings)
        update({ settings })
        return settings
      }

      // ----------------------------------------------------------------
      // Peak state: holiday fetch, 1s tick, transition announcement
      // ----------------------------------------------------------------

      const peakHolidayCache = new Map()

      function peakCacheKey(year) {
        return `dsh-notify-web:peak-holiday:${year}`
      }

      function readCachedHoliday(year) {
        const memory = peakHolidayCache.get(year)
        if (memory && now() - memory.at < PEAK_HOLIDAY_TTL_HOURS * 3600 * 1000) {
          return memory.data
        }
        const raw = safe(() => storage?.getItem(peakCacheKey(year)), null)
        if (!raw) return null
        const parsed = safe(() => JSON.parse(raw), null)
        if (!parsed || typeof parsed.at !== 'number') return null
        const ttlHours = peakIsUnpublished(parsed.data)
          ? PEAK_HOLIDAY_TTL_UNPUBLISHED_HOURS
          : PEAK_HOLIDAY_TTL_HOURS
        if (now() - parsed.at > ttlHours * 3600 * 1000) return null
        peakHolidayCache.set(year, { at: parsed.at, data: parsed.data })
        return parsed.data
      }

      function writeCachedHoliday(year, data) {
        const at = now()
        peakHolidayCache.set(year, { at, data })
        safe(() => storage?.setItem(peakCacheKey(year), JSON.stringify({ at, data })))
      }

      function validateHolidayPayload(payload, year) {
        if (!payload || typeof payload !== 'object') return null
        if (Number(payload.year) !== Number(year)) return null
        if (!Array.isArray(payload.days)) return null
        const days = payload.days.filter(
          (day) => day && typeof day.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day.date),
        )
        if (days.length === 0) return null
        const papers = Array.isArray(payload.papers) ? payload.papers : []
        return { year: Number(year), papers, days }
      }

      async function fetchHoliday(year, signal) {
        if (typeof fetchFn !== 'function') return null
        const url = PEAK_HOLIDAY_URL.replace('{year}', String(year))
        const controller = new AbortController()
        const timer = setTimeoutFn(() => safe(() => controller.abort()), PEAK_HOLIDAY_TIMEOUT_MS)
        const onAbort = () => safe(() => controller.abort())
        if (signal) signal.addEventListener('abort', onAbort)
        try {
          const response = await fetchFn(url, { signal: controller.signal, cache: 'no-cache' })
          if (!response || !response.ok) return null
          const payload = await response.json()
          const validated = validateHolidayPayload(payload, year)
          if (validated) writeCachedHoliday(year, validated)
          return validated
        } catch {
          return null
        } finally {
          clearTimeoutFn(timer)
          if (signal) signal.removeEventListener('abort', onAbort)
        }
      }

      function recomputePeak(holidayData) {
        const at = now()
        const decision = peakDecision(at, holidayData)
        const nextChangeAt = peakNextChange(at, holidayData)
        const previous = getState().peak
        update({
          peak: {
            ...previous,
            isPeak: decision.isPeak,
            reason: decision.reason,
            confidence: decision.confidence,
            nextChangeAt,
            holidayYear: holidayData ? holidayData.year : null,
            unpublished: peakIsUnpublished(holidayData),
            loaded: true,
          },
        })
        return decision
      }

      function peakAnnounce(wasPeak, isPeak) {
        const settings = getState().settings
        if (!settings.notifyOnPeakChange) return
        // The same route gate as the chip: announcing a DeepSeek billing
        // transition while a third-party route is selected is simply wrong.
        if (!peakAppliesToRoute(readActiveProvider(doc), settings)) return
        if (wasPeak === isPeak) return
        const lang = currentLang()
        const title = isPeak
          ? translate(lang, 'peak.peak')
          : translate(lang, 'peak.offPeak')
        const body = translate(lang, isPeak ? 'peak.peakHint' : 'peak.offPeakHint')
        // Reuse the single notification channel: Chrome first, toast fallback.
        emitPeakEvent(title, body)
      }

      function emitPeakEvent(title, body) {
        const settings = getState().settings
        const delivered = showOsNotification(
          'peak',
          `DeepSeek ${title}`,
          body,
          settings,
          () => showFallbackToast('peak', `DeepSeek ${title}`, body),
        )
        if (!delivered) showFallbackToast('peak', `DeepSeek ${title}`, body)
        update({ lastEventAt: now() })
        syncBadge()
      }

      function syncBadge() {
        // Badge the tab while a peak window is active so a background tab still
        // signals the state; clear it when off-peak. setAppBadge is absent on
        // many browsers, so this is opportunistic only.
        const badge = safe(() => nav?.setAppBadge, undefined)
        const clear = safe(() => nav?.clearAppBadge, undefined)
        const peak = getState().peak
        const official = peakAppliesToRoute(readActiveProvider(doc), getState().settings)
        if (typeof badge === 'function' && typeof clear === 'function') {
          if (peak.isPeak && official) safe(() => badge.call(nav, 1))
          else safe(() => clear.call(nav))
        }
        const title = safe(() => doc?.title, '')
        // Keep a peak marker in the tab title as the second attention channel.
        if (typeof title === 'string') {
          const base = title.replace(/^●\s*/, '').replace(/^DeepSeek · /, '')
          const next = peak.isPeak && official ? `● ${base}` : base
          if (next !== title) safe(() => { doc.title = next })
        }
      }

      function peakTick() {
        const before = getState().peak
        const cached = readCachedHoliday(beijingYear(now()))
        const decision = recomputePeak(cached)
        if (before.loaded && before.isPeak !== decision.isPeak) {
          peakAnnounce(before.isPeak, decision.isPeak)
        }
        syncBadge()
      }

      let peakTimer = null

      function startPeak() {
        const year = beijingYear(now())
        const cached = readCachedHoliday(year)
        recomputePeak(cached)
        syncBadge()
        // Fetch in the background; the first paint never waits on the network.
        peakLoadPromise = fetchHoliday(year).then((fresh) => {
          if (fresh) {
            const decision = recomputePeak(fresh)
            syncBadge()
            if (!getState().peak.isPeak && decision.isPeak) syncBadge()
          }
          return fresh
        })
        peakTimer = setIntervalFn(() => {
          safe(peakTick)
          // Re-check the holiday payload once an hour; the tick itself is cheap.
          if (now() - peakHolidayCheckedAt > 3600 * 1000) {
            peakHolidayCheckedAt = now()
            fetchHoliday(beijingYear(now())).then((fresh) => {
              if (fresh) recomputePeak(fresh)
            })
          }
        }, PEAK_TICK_MS)
      }

      let peakHolidayCheckedAt = 0
      let peakLoadPromise = Promise.resolve(null)

      function stopPeak() {
        if (peakTimer !== null) {
          clearIntervalFn(peakTimer)
          peakTimer = null
        }
      }

      function setPeakView(view) {
        const peak = getState().peak
        if (peak.view === view) return peak.view
        update({ peak: { ...peak, view } })
        return view
      }

      function togglePeakView() {
        const peak = getState().peak
        return setPeakView(peak.view === 'timer' ? 'summary' : 'timer')
      }

      function peakSnapshot() {
        const peak = getState().peak
        const at = now()
        return {
          ...peak,
          remaining: peakRemainingParts(peak.nextChangeAt, at),
          timerText: peak.nextChangeAt
            ? peakTimerText(peak.nextChangeAt, at)
            : translate(currentLang(), 'peak.unknown'),
        }
      }

      function sessionRow(sessionId) {
        return safe(() => sources.session?.(sessionId), undefined)
      }

      function isRoot(row) {
        if (!row) return true
        return !row.parentId && row.origin !== 'subagent'
      }

      function enabledFor(kind, settings) {
        if (kind === 'complete') return settings.notifyOnComplete
        if (kind === 'approval') return settings.notifyOnApproval
        if (kind === 'question') return settings.notifyOnQuestion
        if (kind === 'error') return settings.notifyOnError
        return true
      }

      function consumeCooldown(kind, sessionId, ms) {
        if (!ms || ms <= 0) return true
        const key = `${kind}:${sessionId || 'global'}`
        const at = now()
        const previous = cooldowns.get(key)
        if (previous !== undefined && at - previous < ms) return false
        cooldowns.set(key, at)
        return true
      }

      function recentRequest(key) {
        if (!key) return false
        const at = now()
        for (const [name, stamp] of recentRequests) {
          if (at - stamp > REQUEST_TTL) recentRequests.delete(name)
        }
        if (recentRequests.has(key)) return true
        recentRequests.set(key, at)
        return false
      }

      function sessionTitle(row) {
        return sanitizeText(row?.displayTitle || row?.title || '', MAX_TITLE)
      }

      function buildBody(kind, row, options) {
        const body =
          kind === 'error' && options?.message
            ? sanitizeText(options.message, MAX_ERROR)
            : translate(currentLang(), `body.${kind}`)
        const title = sessionTitle(row)
        return title ? `${body}\n${title}` : body
      }

      function showOsNotification(kind, title, body, settings, onFailure) {
        if (!NotificationCtor || NotificationCtor.permission !== 'granted') return false
        try {
          const notification = new NotificationCtor(title, {
            ...notificationOptionsFor(kind, settings, environment, now, randomId),
            body,
          })
          notification.onclick = () => {
            safe(() => notification.close())
            safe(() => win?.focus?.())
          }
          let failureReported = false
          notification.onerror = () => {
            if (failureReported) return
            failureReported = true
            safe(() => onFailure?.())
          }
          // Return the OS notification slot when the user ignores it; the OS
          // notification list (Action Center, Notification Center) keeps it.
          setTimeoutFn(() => safe(() => notification.close()), 8000)
          return true
        } catch {
          return false
        }
      }

      function showFallbackToast(kind, title, body) {
        const toast = {
          id: `toast-${now()}-${Math.random().toString(36).slice(2, 7)}`,
          kind,
          title,
          body,
          at: now(),
        }
        update({ fallbackToast: toast })
        return toast.id
      }

      function dismissFallbackToast(id) {
        const current = getState().fallbackToast
        if (!current) return
        if (id !== undefined && current.id !== id) return
        update({ fallbackToast: null })
      }

      async function requestNotifications() {
        if (!NotificationCtor || typeof NotificationCtor.requestPermission !== 'function') {
          update({ permission: permissionOf() })
          return 'unsupported'
        }
        try {
          await NotificationCtor.requestPermission()
        } catch {
          // A browser may reject without a gesture; the state below is authoritative.
        }
        const permission = permissionOf()
        update({ permission })
        return permission
      }

      // The first real event may ask Chrome for permission once per page if the
      // user has not answered yet. Browsers may still require a gesture; the
      // toast fallback covers that until the user presses Enable in Settings.
      function autoRequestPermission() {
        if (autoPermissionRequested) return false
        if (!NotificationCtor || typeof NotificationCtor.requestPermission !== 'function') return false
        autoPermissionRequested = true
        Promise.resolve(NotificationCtor.requestPermission())
          .then(() => update({ permission: permissionOf() }))
          .catch((error) => logger?.warn?.('[notify-for-chrome] permission request failed', error))
        return true
      }

      function emit(kind, sessionId, options = {}) {
        if (!started && !options.force) return false
        const focused = safe(() => doc?.hasFocus?.(), false)
        // A focused tab must notify even when a stale lease from an older tab
        // still owns leader election; the leader is the background fallback.
        if (!options.force && !getState().leader && !focused) return false
        const settings = getState().settings
        if (!options.force && !enabledFor(kind, settings)) return false
        if (!options.force && kind === 'complete' && settings.suppressWhenFocused && focused) return false

        const row = options.row ?? sessionRow(sessionId)
        if (
          !options.force &&
          (kind === 'complete' || kind === 'error') &&
          !settings.notifyOnSubagents &&
          !isRoot(row)
        ) {
          return false
        }
        if (!options.force && !consumeCooldown(kind, sessionId, settings.completeCooldownMs)) return false

        const lang = currentLang()
        const title = translate(lang, `title.${kind}`)
        const body = buildBody(kind, row, options)
        const permission = permissionOf()
        if (permission !== getState().permission) update({ permission })

        const markFallback = () => {
          showFallbackToast(kind, title, body)
          update({
            lastDelivery: { ...(getState().lastDelivery || {}), kind, sessionId: sessionId ?? null, permission, osShown: false, fallback: true },
          })
        }

        let osShown = false
        if (permission === 'granted') {
          osShown = showOsNotification(kind, title, body, settings, markFallback)
        }
        // Chrome notification first; the native DSH toast is the silent fallback.
        if (!osShown) markFallback()
        if (!osShown && permission === 'default') autoRequestPermission()

        const at = now()
        update({
          lastEventAt: at,
          lastDelivery: {
            kind,
            sessionId: sessionId ?? null,
            permission,
            osShown,
            fallback: !osShown,
            at,
          },
        })
        return osShown
      }

      function handleStatus(sessionId, running) {
        try {
          const at = now()
          update({ lastStatusEvent: { sessionId: sessionId ?? null, running, at } })
          logger?.log?.('[notify-for-chrome] status event', {
            sessionId,
            running,
            leader: getState().leader,
            focused: safe(() => doc?.hasFocus?.(), false),
            platform: environment.platform,
            installState: environment.installState,
          })
          if (running) {
            cooldowns.delete(`complete:${sessionId}`)
            return
          }
          emit('complete', sessionId)
        } catch (error) {
          logger?.warn?.('[notify-for-chrome] status handler failed', error)
        }
      }

      function handleError(sessionId, message) {
        try {
          emit('error', sessionId, { message })
        } catch (error) {
          logger?.warn?.('[notify-for-chrome] error handler failed', error)
        }
      }

      function handleApproval(scope, request, next) {
        try {
          const sessionId = safe(() => sources.scopeOf?.(scope), undefined) || request?.sessionId
          const key = request?.callId || request?.id || request?.requestId
          if (!recentRequest(key ? `approval:${key}` : '')) emit('approval', sessionId, { request })
        } catch (error) {
          logger?.warn?.('[notify-for-chrome] approval handler failed', error)
        }
        return next()
      }

      function handleQuestion(scope, request, next) {
        try {
          const sessionId = safe(() => sources.scopeOf?.(scope), undefined) || request?.sessionId
          const key = request?.callId || request?.id || request?.requestId
          if (!recentRequest(key ? `question:${key}` : '')) emit('question', sessionId, { request })
        } catch (error) {
          logger?.warn?.('[notify-for-chrome] question handler failed', error)
        }
        return next()
      }

      function createLeader() {
        let leader = false
        let stopped = false
        let releaseLock = null
        let leaseTimer = null
        const tabId = randomId()

        function publish(value) {
          if (leader === value) return
          leader = value
          update({ leader: value })
        }

        function readLease() {
          return readJson(LEADER_KEY, null)
        }

        function writeLease(value) {
          writeJson(LEADER_KEY, value)
        }

        function tickLease() {
          if (stopped) return
          const at = now()
          const lease = readLease()
          if (!lease || !lease.id || Number(lease.expires) <= at || lease.id === tabId) {
            writeLease({ id: tabId, expires: at + 10000 })
            publish(true)
            return
          }
          publish(false)
        }

        function onStorage(event) {
          if (!event || event.key === LEADER_KEY || event.key === null) tickLease()
        }

        function startLease() {
          if (stopped || leaseTimer !== null) return
          tickLease()
          leaseTimer = setIntervalFn(tickLease, 3000)
          win?.addEventListener?.('storage', onStorage)
        }

        function startLocks() {
          try {
            const request = locks.request(LEADER_LOCK, { mode: 'exclusive' }, async () => {
              if (stopped) return
              publish(true)
              await new Promise((resolve) => {
                releaseLock = resolve
              })
              publish(false)
            })
            Promise.resolve(request).catch(() => {
              if (!stopped) startLease()
            })
          } catch {
            startLease()
          }
        }

        function start() {
          if (stopped) return
          if (locks && typeof locks.request === 'function') startLocks()
          else startLease()
        }

        function stop() {
          stopped = true
          if (releaseLock) {
            const release = releaseLock
            releaseLock = null
            safe(release)
          }
          if (leaseTimer !== null) {
            clearIntervalFn(leaseTimer)
            leaseTimer = null
          }
          win?.removeEventListener?.('storage', onStorage)
          const lease = readLease()
          if (lease && lease.id === tabId) safe(() => storage?.removeItem(LEADER_KEY))
          publish(false)
        }

        return { start, stop, isLeader: () => leader }
      }

      const leader = createLeader()

      function refresh() {
        const lang = currentLang()
        const permission = permissionOf()
        update({
          permission,
          secureContext: secureContextOf(),
          leader: leader.isLeader(),
          lang,
          environment,
        })
        if (lang !== getState().lang) update({ lang })
      }

      function onStorage(event) {
        if (!event || event.key === SETTINGS_KEY || event.key === null) {
          update({ settings: loadSettings() })
        }
      }

      function start() {
        if (started) return
        started = true
        leader.start()
        const bind = (source, handler) => {
          try {
            return typeof source === 'function' ? source(handler) : undefined
          } catch (error) {
            logger?.warn?.('[notify-for-chrome] subscription failed', error)
            return undefined
          }
        }
        disposers = [
          bind(sources.status, handleStatus),
          bind(sources.error, handleError),
          bind(sources.approval, function (request, next) {
            return handleApproval(this, request, next)
          }),
          bind(sources.question, function (request, next) {
            return handleQuestion(this, request, next)
          }),
        ].filter(Boolean)
        if (typeof locale?.subscribe === 'function') {
          localeDispose = safe(() => locale.subscribe(() => {
            const lang = currentLang()
            if (lang !== getState().lang) update({ lang })
          }), undefined)
        }
        win?.addEventListener?.('storage', onStorage)
        win?.addEventListener?.('focus', refresh)
        startPeak()
        refresh()
      }

      function stop() {
        if (!started) return
        started = false
        for (const dispose of disposers.splice(0)) safe(dispose)
        if (typeof localeDispose === 'function') {
          safe(localeDispose)
          localeDispose = null
        }
        leader.stop()
        stopPeak()
        win?.removeEventListener?.('storage', onStorage)
        win?.removeEventListener?.('focus', refresh)
      }

      const core = {
        start,
        stop,
        refresh,
        getState,
        subscribe,
        actions: {
          requestNotifications,
          test: async () => {
            const osShown = emit('test', 'test', { force: true })
            return osShown ? 'chrome' : 'fallback'
          },
          setSetting(key, value) {
            return updateSettings({ ...getState().settings, [key]: value })
          },
          resetSettings() {
            const settings = normalizeSettings({ ...DEFAULT_SETTINGS, ...(config || {}) })
            saveSettings(settings)
            update({ settings })
            return settings
          },
          dismissFallbackToast,
          togglePeakView,
          setPeakView,
          refreshPeak: () => peakTick(),
        },
        peak: {
          snapshot: peakSnapshot,
          toggleView: togglePeakView,
          setView: setPeakView,
          load: () => peakLoadPromise,
          decision: (utcMs, data) => peakDecision(utcMs, data),
          nextChange: (utcMs, data) => peakNextChange(utcMs, data),
        },
        __handlers: { handleStatus, handleError, handleApproval, handleQuestion },
      }
      return core
    }

    // ------------------------------------------------------------------
    // UI adapters (native DSH primitives + DSH tokens only)
    // ------------------------------------------------------------------

    // Typography comes from the live DSH content-size tokens (never a literal
    // size, never a font family). Layout values are plain numbers.
    const CONTENT_TEXT = {
      fontSize: 'var(--dsh-content-font-size, 14px)',
      lineHeight: 'calc(22px + var(--dsh-content-font-delta, 0px))',
    }
    const SECONDARY_TEXT = {
      fontSize: 'var(--dsh-content-font-size-secondary, 13px)',
      lineHeight: 'calc(20px + var(--dsh-content-font-delta-secondary, 0px))',
    }

    const styles = {
      section: {
        display: 'grid',
        gap: 16,
        padding: '4px 0 16px',
        minWidth: 0,
        color: 'var(--dsw-alias-label-primary)',
        ...CONTENT_TEXT,
      },
      header: { display: 'grid', gap: 4, minWidth: 0 },
      heading: { margin: 0, fontWeight: 500, color: 'var(--dsw-alias-label-primary)', ...CONTENT_TEXT },
      hint: { margin: 0, color: 'var(--dsw-alias-label-tertiary)', ...SECONDARY_TEXT },
      card: {
        display: 'grid',
        gap: 10,
        minWidth: 0,
        padding: 12,
        border: '0.5px solid var(--dsw-alias-border-l3)',
        borderRadius: 'var(--dsw-radius-lg)',
        background: 'var(--dsw-alias-bg-layer-2)',
      },
      cardTitle: { margin: 0, fontWeight: 500, color: 'var(--dsw-alias-label-primary)', ...CONTENT_TEXT },
      statusLine: { display: 'flex', alignItems: 'center', gap: 8, minWidth: 0, color: 'var(--dsw-alias-label-secondary)', ...SECONDARY_TEXT },
      actions: { display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center', minWidth: 0 },
      row: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 24, minWidth: 0 },
      rowText: { display: 'grid', gap: 2, minWidth: 0 },
      rowLabel: { color: 'var(--dsw-alias-label-primary)', ...CONTENT_TEXT },
      rowHint: { margin: 0, color: 'var(--dsw-alias-label-tertiary)', ...SECONDARY_TEXT },
      control: { display: 'flex', alignItems: 'center', gap: 8, flex: '0 0 auto' },
      number: { width: 88 },
      meta: { display: 'grid', gap: 2, minWidth: 0 },
      metaRow: { display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 16, minWidth: 0 },
      metaLabel: { color: 'var(--dsw-alias-label-tertiary)', ...SECONDARY_TEXT },
      metaValue: { color: 'var(--dsw-alias-label-secondary)', textAlign: 'right', minWidth: 0, ...SECONDARY_TEXT },
    }

    function useCoreState(core) {
      const [state, setState] = React.useState(() => core.getState())
      React.useEffect(() => core.subscribe(setState), [core])
      return state
    }

    /** Human name for a detected engine family. */
    function browserName(browser) {
      if (browser === 'chromium') return 'Chromium'
      if (browser === 'firefox') return 'Firefox'
      if (browser === 'safari') return 'Safari'
      return 'Unknown'
    }

    function platformLabel(lang, platform) {
      const key =
        platform === 'windows'
          ? 'environment.platformWindows'
          : platform === 'macos'
            ? 'environment.platformMacos'
            : platform === 'linux'
              ? 'environment.platformLinux'
              : platform === 'android'
                ? 'environment.platformAndroid'
                : 'environment.platformOther'
      return translate(lang, key)
    }

    function permissionTagTone(permission) {
      if (permission === 'granted') return 'success'
      if (permission === 'denied') return 'danger'
      if (permission === 'insecure' || permission === 'default') return 'warning'
      return 'neutral'
    }

    function permissionStatusKey(permission) {
      if (permission === 'granted') return 'status.granted'
      if (permission === 'denied') return 'status.denied'
      if (permission === 'insecure') return 'status.insecure'
      if (permission === 'unsupported') return 'status.unsupported'
      return 'status.default'
    }

    function permissionHintKey(permission, platform) {
      const windows = platform === 'windows'
      if (permission === 'insecure') return 'hint.insecure'
      if (permission === 'unsupported') return 'hint.unsupported'
      if (permission === 'denied') return windows ? 'hint.deniedWindows' : 'hint.denied'
      if (permission === 'default') return windows ? 'hint.permissionWindows' : 'hint.permissionGeneric'
      return ''
    }

    function makeSettingsSection(core) {
      return function NotifyForChromeSettings() {
        const state = useCoreState(core)
        const [message, setMessage] = React.useState('')
        const [busy, setBusy] = React.useState(false)
        const lang = state.lang
        const t = (key, vars) => translate(lang, key, vars)
        const h = React.createElement
        const settings = state.settings
        const environment = state.environment

        async function run(operation) {
          setBusy(true)
          setMessage('')
          try {
            const text = await operation()
            if (typeof text === 'string' && text.length > 0) setMessage(text)
          } catch (error) {
            setMessage(error instanceof Error ? error.message : String(error))
          } finally {
            setBusy(false)
          }
        }

        function toggleRow(key, title, hint) {
          return h(
            'div',
            { key, style: styles.row },
            h(
              'div',
              { style: styles.rowText },
              h('div', { style: styles.rowLabel }, title),
              hint ? h('p', { style: styles.rowHint }, hint) : null,
            ),
            h('div', { style: styles.control }, h(Switch, {
              checked: settings[key] === true,
              label: title,
              onChange: (checked) => core.actions.setSetting(key, checked),
            })),
          )
        }

        function metaRow(key, label, value) {
          return h(
            'div',
            { key, style: styles.metaRow },
            h('span', { style: styles.metaLabel }, label),
            h('span', { style: styles.metaValue }, value),
          )
        }

        const hintKey = permissionHintKey(state.permission, environment.platform)
        const hint = hintKey ? t(hintKey) : ''
        const lastEvent = state.lastStatusEvent
          ? `${state.lastStatusEvent.sessionId} · ${state.lastStatusEvent.running ? t('environment.running') : t('environment.finished')}`
          : t('environment.none')
        const lastDelivery = state.lastDelivery
          ? `${state.lastDelivery.osShown ? t('environment.chrome') : t('environment.toast')} · ${state.lastDelivery.kind}`
          : t('environment.none')

        return h(
          'section',
          { style: styles.section },
          h(
            'header',
            { style: styles.header },
            h('h2', { style: styles.heading }, t('sectionTitle')),
            h('p', { style: styles.hint }, t('sectionHint')),
          ),
          h(
            'section',
            { style: styles.card },
            h('h3', { style: styles.cardTitle }, t('statusTitle')),
            h(
              'div',
              { style: styles.statusLine },
              h(Tag, { tone: permissionTagTone(state.permission) }, t(permissionStatusKey(state.permission))),
              h('span', null, state.leader ? t('status.leader') : t('status.waiting')),
            ),
            hint ? h('p', { style: styles.hint }, hint) : null,
            h(
              'div',
              { style: styles.actions },
              // A capability that is gone is hidden, not shown as a broken button.
              state.permission === 'default'
                ? h(Button, {
                    variant: 'primary',
                    disabled: busy,
                    onClick: () =>
                      run(async () => {
                        const permission = await core.actions.requestNotifications()
                        return permission === 'granted' ? t('action.enabled') : t('action.notEnabled')
                      }),
                  }, t('action.enable'))
                : null,
              h(Button, {
                variant: 'outline',
                disabled: busy,
                onClick: () =>
                  run(async () => {
                    const channel = await core.actions.test()
                    return channel === 'chrome' ? t('action.testChrome') : t('action.testFallback')
                  }),
              }, t('action.test')),
            ),
            message ? h('p', { style: styles.hint }, message) : null,
          ),
          h(
            'section',
            { style: styles.card },
            h('h3', { style: styles.cardTitle }, t('peak.sectionTitle')),
            h('p', { style: styles.hint }, t('peak.sectionHint')),
            toggleRow('showPeakChip', t('peak.chipRow'), t('peak.chipRowHint')),
            toggleRow('notifyOnPeakChange', t('peak.announceRow'), t('peak.announceRowHint')),
            toggleRow('peakOnAnyProvider', t('peak.anyProviderRow'), t('peak.anyProviderRowHint')),
            h('p', { style: styles.hint }, t('peak.caveat')),
          ),
          h(
            'section',
            { style: styles.card },
            h('h3', { style: styles.cardTitle }, t('kinds.title')),
            toggleRow('notifyOnComplete', t('kinds.complete'), t('kinds.completeHint')),
            toggleRow('notifyOnApproval', t('kinds.approval'), t('kinds.approvalHint')),
            toggleRow('notifyOnQuestion', t('kinds.question'), t('kinds.questionHint')),
            toggleRow('notifyOnError', t('kinds.error'), t('kinds.errorHint')),
            toggleRow('notifyOnSubagents', t('kinds.subagents'), t('kinds.subagentsHint')),
            toggleRow('suppressWhenFocused', t('kinds.suppress'), t('kinds.suppressHint')),
            toggleRow('requireInteractionForApproval', t('kinds.requireInteraction'), t('kinds.requireInteractionHint')),
            h(
              'div',
              { style: styles.row },
              h(
                'div',
                { style: styles.rowText },
                h('div', { style: styles.rowLabel }, t('cooldown.label')),
                h('p', { style: styles.rowHint }, t('cooldown.hint')),
              ),
              h('div', { style: styles.control }, h(Input, {
                type: 'number',
                min: 0,
                max: 60,
                step: 1,
                style: styles.number,
                'aria-label': t('cooldown.unit'),
                value: Math.round(settings.completeCooldownMs / 1000),
                onChange: (event) =>
                  core.actions.setSetting(
                    'completeCooldownMs',
                    clamp(Number(event.target.value), 0, 60) * 1000,
                  ),
              })),
            ),
          ),
          h(
            'section',
            { style: styles.card },
          h('h3', { style: styles.cardTitle }, t('browser.title')),
          h(
            'div',
            { style: styles.row },
            h(
              'div',
              { style: styles.rowText },
              h(
                'div',
                { style: styles.rowLabel },
                environment.browser === 'chromium'
                  ? t('browser.chromium')
                  : t('browser.other', { name: browserName(environment.browser) }),
              ),
              h(
                'p',
                { style: styles.rowHint },
                environment.browser === 'chromium'
                  ? t('browser.chromiumHint')
                  : t('browser.otherHint'),
              ),
            ),
            h('div', { style: styles.control }, h(Tag, {
              tone: environment.browser === 'chromium' ? 'success' : 'warning',
              children: environment.browser === 'chromium' ? 'Chromium' : browserName(environment.browser),
            })),
          ),
          ),
          h(
            'section',
            { style: styles.card },
            h('h3', { style: styles.cardTitle }, t('environment.title')),
            h(
              'div',
              { style: styles.meta },
              metaRow('platform', t('environment.platform'), platformLabel(lang, environment.platform)),
              h('p', { style: styles.hint }, t('environment.platformHint')),
              metaRow(
                'install',
                t('environment.install'),
                environment.installState === 'installed'
                  ? t('environment.installInstalled')
                  : t('environment.installBrowser'),
              ),
              metaRow('permission', t('environment.permission'), state.permission),
              metaRow('leader', t('environment.leader'), state.leader ? t('environment.leaderThis') : t('environment.leaderOther')),
              metaRow('lastEvent', t('environment.lastEvent'), lastEvent),
              metaRow('lastDelivery', t('environment.lastDelivery'), lastDelivery),
            ),
            h(
              'div',
              { style: styles.actions },
              h(Button, {
                variant: 'ghost',
                onClick: () =>
                  run(async () => {
                    core.actions.resetSettings()
                    return t('action.resetDone')
                  }),
              }, t('action.reset')),
            ),
          ),
        )
      }
    }

    // ------------------------------------------------------------------
    // 7-segment peak chip
    //
    // Owner instruction 2026-11-06: reuse the Windows prototype's 7-segment
    // look for an in-app countdown, because a page cannot force its own window
    // to the foreground (measured: window.focus() is a silent no-op).
    //
    // Rendered as inline SVG rather than a font: the plugin ships no font, sets
    // no family, and every stroke takes its colour from a DSH token.
    // ------------------------------------------------------------------

    function sevenSegmentChar(char, options) {
      const h = React.createElement
      const height = options.height
      const unit = height / 18
      const thickness = 1.9 * unit
      const pad = thickness / 2
      const isColon = char === ':'
      const width = isColon ? 3 * unit + thickness : 10 * unit + thickness
      const boxHeight = 18 * unit + thickness
      const colour = options.colour
      const ghost = options.ghost
      const opacity = options.opacity

      if (isColon) {
        const dots = []
        for (const cy of [0.38, 0.68]) {
          dots.push(
            h('circle', {
              key: `dot-${cy}`,
              cx: pad + 1.1 * unit,
              cy: 18 * unit * cy + pad,
              r: 1.1 * unit,
              fill: colour,
              opacity,
            }),
          )
        }
        return h(
          'svg',
          {
            key: options.key,
            width,
            height: boxHeight,
            viewBox: `0 0 ${width} ${boxHeight}`,
            'aria-hidden': 'true',
            style: { display: 'block', marginRight: options.gap },
          },
          ...dots,
        )
      }

      const segments = []
      const lit = sevenSegmentLit(char)
      const ghostSegments = ghost ? Object.keys(SEVEN_SEGMENT_POINTS) : []
      const draw = (name, on) => {
        const point = SEVEN_SEGMENT_POINTS[name]
        segments.push(
          h('line', {
            key: `${name}-${on ? 'on' : 'off'}`,
            x1: point[0] * unit + pad,
            y1: point[1] * unit + pad,
            x2: point[2] * unit + pad,
            y2: point[3] * unit + pad,
            stroke: on ? colour : ghost,
            strokeWidth: thickness,
            strokeLinecap: 'round',
            opacity: on ? opacity : 1,
          }),
        )
      }
      if (ghost) for (const name of ghostSegments) draw(name, lit.includes(name))
      else for (const name of lit) draw(name, true)

      return h(
        'svg',
        {
          key: options.key,
          width,
          height: boxHeight,
          viewBox: `0 0 ${width} ${boxHeight}`,
          'aria-hidden': 'true',
          style: { display: 'block', marginRight: options.gap },
        },
        ...segments,
      )
    }

    function sevenSegmentText(text, options) {
      const h = React.createElement
      const chars = String(text).split('')
      return h(
        'span',
        {
          style: {
            display: 'inline-flex',
            alignItems: 'center',
            lineHeight: 0,
            // Tabular baseline: the digit cells keep a constant advance because
            // every glyph shares one geometry box.
            fontVariantNumeric: 'tabular-nums',
          },
        },
        ...chars.map((char, index) =>
          sevenSegmentChar(char, {
            key: `seg-${index}`,
            height: options.height,
            colour: options.colour,
            ghost: options.ghost,
            opacity: options.opacity,
            gap: index === chars.length - 1 ? 0 : Math.max(1, Math.round(options.height * 0.1)),
          }),
        ),
      )
    }

    /** Read the provider id the composer currently shows, or ''. */
    function readActiveProvider(doc) {
      if (!doc || typeof doc.querySelector !== 'function') return ''
      const node = safe(() => doc.querySelector(PROVIDER_PROBE), null)
      if (!node || typeof node.getAttribute !== 'function') return ''
      return String(safe(() => node.getAttribute('data-provider-id'), '') ?? '')
    }

    /** Whether the active route is an official DeepSeek route. */
    function isOfficialDeepSeekProvider(providerId) {
      return OFFICIAL_DEEPSEEK_PROVIDER_IDS.includes(String(providerId || ''))
    }

    /**
     * Whether the peak clock applies to the active route.
     *
     * Default: official DeepSeek routes only. The owner may opt in to showing
     * it everywhere, because a third-party route may also bill this model — but
     * the default must not claim a discount that belongs to someone else's
     * price sheet.
     * @param providerId - the id the model selector currently shows.
     * @param settings - the live settings snapshot.
     * @returns whether the peak surface may render.
     */
    function peakAppliesToRoute(providerId, settings) {
      if (settings && settings.peakOnAnyProvider === true) return true
      return isOfficialDeepSeekProvider(providerId)
    }

    /**
     * Watch the composer's provider selection.
     *
     * The selector re-renders its trigger label with a fresh
     * `data-provider-id`, so an attribute-filtered MutationObserver reports
     * every route change without polling.
     * @param doc - the document to observe.
     * @param onChange - called on every observed selection change.
     * @returns disconnect.
     */
    function watchActiveProvider(doc, onChange) {
      if (!doc || typeof MutationObserver === 'undefined' || typeof doc.querySelector !== 'function') {
        return () => {}
      }
      let last = readActiveProvider(doc)
      const observer = new MutationObserver(() => {
        const next = readActiveProvider(doc)
        if (next === last) return
        last = next
        safe(onChange)
      })
      observer.observe(doc.body ?? doc.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['data-provider-id', 'data-model-id'],
      })
      return () => observer.disconnect()
    }

    function makePeakChip(core) {
      return function PeakChip() {
        const state = useCoreState(core)
        const lang = state.lang
        const t = (key, vars) => translate(lang, key, vars)
        const h = React.createElement
        const peak = state.peak
        const settings = state.settings
        const nowMs = Date.now()

        // Route gate: the peak/off-peak clock only describes DeepSeek's own
        // billing. Read at mount (the composer may already carry the attribute)
        // and follow every selection change.
        const [activeProvider, setActiveProvider] = React.useState(() =>
          readActiveProvider(doc),
        )
        React.useEffect(() => {
          const read = () => setActiveProvider(readActiveProvider(doc))
          read()
          return watchActiveProvider(doc, read)
        }, [])

        if (!settings.showPeakChip) return null
        if (!peakAppliesToRoute(activeProvider, settings)) return null

        const at = peak.nextChangeAt
        const timerText = at
          ? peakTimerText(at, nowMs)
          : t('peak.unknown')
        const isPeak = peak.isPeak
        // Off-peak is the discounted state, so it is green; peak is the
        // warning state and takes the DSH error token.
        const colour = isPeak
          ? 'var(--dsw-alias-state-error-primary)'
          : 'var(--dsw-alias-state-success-primary)'
        const ghost = 'var(--dsw-alias-border-l2)'
        const statusLabel = isPeak ? t('peak.peak') : t('peak.offPeak')
        const hint = isPeak ? t('peak.peakHint') : t('peak.offPeakHint')
        const badge = peak.confidence === 'estimated'
          ? (peak.unpublished ? t('peak.preAnnouncement') : t('peak.estimated'))
          : ''
        const title = `${t('peak.label')} · ${statusLabel}${badge ? ` (${badge})` : ''}`

        const chip = {
          display: 'inline-flex',
          alignItems: 'center',
          gap: 8,
          padding: '4px 10px',
          borderRadius: 10,
          border: '1px solid var(--dsw-alias-border-l1)',
          background: 'var(--dsw-alias-bg-layer-1)',
          color: 'var(--dsw-alias-label-primary)',
          cursor: 'pointer',
          userSelect: 'none',
          whiteSpace: 'nowrap',
          maxWidth: 260,
          minWidth: 0,
        }
        const labelStyle = {
          fontSize: 'var(--dsh-content-font-size-secondary, 13px)',
          lineHeight: 'calc(20px + var(--dsh-content-font-delta-secondary, 0px))',
          color: 'var(--dsw-alias-label-secondary)',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
        }

        const onActivate = () => {
          const next = core.peak.toggleView()
          return next
        }

        const body = peak.view === 'summary'
          ? h('span', { style: labelStyle }, hint)
          : sevenSegmentText(timerText, { height: 14, colour, ghost, opacity: 0.92 })

        return h(
          'button',
          {
            type: 'button',
            title: `${title}\n${hint}`,
            'aria-label': `${title}. ${t('peak.toggleHint')}`,
            onClick: onActivate,
            style: chip,
          },
          h('span', {
            style: {
              width: 8,
              height: 8,
              borderRadius: 999,
              background: colour,
              flex: '0 0 auto',
            },
          }),
          h('span', { style: labelStyle }, statusLabel),
          body,
        )
      }
    }

    function makeFallbackToast(core) {
      return function NotifyForChromeToast() {
        const state = useCoreState(core)
        const toast = state.fallbackToast
        if (!toast) return null
        const text = `${toast.title} — ${String(toast.body).split('\n').join(' · ')}`
        return React.createElement(Toast, {
          key: toast.id,
          text,
          holdMs: TOAST_HOLD_MS,
          onDone: () => core.actions.dismissFallbackToast(toast.id),
        })
      }
    }

    // Set by apply() so the section label and strings follow the host locale.
    let localeReader = () => ''
    function currentLang() {
      return normalizeLang(safe(localeReader, ''))
    }

    function apply(ctx, config = {}) {
      localeReader = () => String(safe(() => ctx?.locale?.getSnapshot?.()?.active, ''))

      const env = {
        storage: safe(() => window.localStorage, undefined),
        Notification: safe(() => window.Notification, undefined),
        window,
        document,
        navigator: safe(() => window.navigator, undefined),
        matchMedia: safe(() => window.matchMedia?.bind(window), undefined),
        locks: safe(() => window.navigator?.locks, undefined),
        locale: {
          active: () => String(safe(() => ctx?.locale?.getSnapshot?.()?.active, '')),
          subscribe: (listener) => {
            const subscribe = safe(() => ctx?.locale?.subscribe, undefined)
            if (typeof subscribe !== 'function') return () => {}
            const dispose = safe(() => subscribe.call(ctx.locale, listener), undefined)
            return typeof dispose === 'function' ? dispose : () => {}
          },
        },
        now: () => Date.now(),
        setTimeout,
        clearTimeout,
        setInterval,
        clearInterval,
        logger: ctx.logger || console,
      }

      const sources = {
        status: (handler) => ctx.remote.$on('api-session/status', handler),
        error: (handler) => ctx.remote.$on('api-session/error', handler),
        approval: (handler) => ctx.remote.$on('approval/request', handler),
        question: (handler) => ctx.remote.$on('user-questions/request', handler),
        session: (sessionId) => ctx.sessions.list.getSnapshot().byId[sessionId],
        scopeOf: (scope) => ctx.sessions.scopeOf(scope),
      }

      const core = createNotifyCore({ config, env, sources })
      const SettingsSection = makeSettingsSection(core)
      const FallbackToast = makeFallbackToast(core)
      const PeakChip = makePeakChip(core)
      const cleanups = []

      function effect(fn, label) {
        try {
          const dispose = ctx.effect ? ctx.effect(fn, label) : fn()
          if (typeof dispose === 'function') cleanups.push(dispose)
        } catch (error) {
          env.logger?.warn?.(`[notify-for-chrome] effect failed: ${label}`, error)
        }
      }

      core.start()

      function sectionLabel() {
        return translate(currentLang(), 'sectionTitle')
      }

      effect(
        () =>
          ctx.slots.inject('settings.section', () =>
            ctx.slots.register(
              {
                name: 'settings.section',
                id: SECTION_ID,
                // Below the agent-preset section (order 20) and above the
                // OpenCode v2 section (order 60).
                order: 50,
                label: sectionLabel,
              },
              SettingsSection,
            ),
          ),
        'notify-for-chrome: settings',
      )

      effect(
        () =>
          ctx.slots.inject('settings.section.icon', () =>
            ctx.slots.register(
              { name: 'settings.section.icon', id: SECTION_ID },
              function NotifySectionIcon(props) {
                // DSH-native icon name; the plugin ships no icon set of its own.
                return React.createElement(primitives.IconAlarmClockOutlineRegular, {
                  size: props?.size ?? 16,
                })
              },
            ),
          ),
        'notify-for-chrome: settings icon',
      )

      effect(
        () =>
          ctx.slots.inject('shell.overlay', () =>
            ctx.slots.register(
              { name: 'shell.overlay', id: 'dsh-notify-web.toast' },
              FallbackToast,
            ),
          ),
        'notify-for-chrome: fallback toast',
      )

      // The peak chip rides the Session header's right-aligned utilities list.
      // Measured 2026-11-06: `conversation.session.header.utilities` is a
      // list-kind, replaceRisk:none seat already rendering three entries, so an
      // additively registered cell is safe and needs no priority trick.
      effect(
        () =>
          ctx.slots.inject('conversation.session.header.utilities', () =>
            ctx.slots.register(
              { name: 'conversation.session.header.utilities', id: PEAK_CHIP_ID, order: 10 },
              PeakChip,
            ),
          ),
        'notify-for-chrome: peak chip',
      )

      const onVisibility = () => core.refresh()
      if (typeof document !== 'undefined' && document.addEventListener) {
        document.addEventListener('visibilitychange', onVisibility)
        cleanups.push(() => document.removeEventListener('visibilitychange', onVisibility))
      }

      function dispose() {
        for (const cleanup of cleanups.splice(0)) safe(cleanup)
        core.stop()
      }

      globalThis.__dshNotifyChrome = { core, dispose }
      return dispose
    }

    exports.apply = apply
    exports.inject = ['remote', 'sessions', 'slots', 'locale']
    exports.__test = {
      createNotifyCore,
      detectEnvironment,
      normalizeSettings,
      normalizeLang,
      translate,
      notificationOptionsFor,
      defaults: DEFAULT_SETTINGS,
      peakDecision,
      peakNextChange,
      peakRemainingParts,
      peakTimerText,
      peakHolidayIndex,
      beijingDateKey,
      sevenSegmentLit,
      sevenSegmentText,
      makePeakChip,
      PEAK_WINDOWS_UTC,
      PEAK_CHIP_ID,
      OFFICIAL_DEEPSEEK_PROVIDER_IDS,
      PROVIDER_PROBE,
      readActiveProvider,
      isOfficialDeepSeekProvider,
      peakAppliesToRoute,
    }

    return exports
  },
})
