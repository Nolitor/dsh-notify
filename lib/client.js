/**
 * DSH Notify Web — browser half.
 *
 * Two layers:
 *   1. createNotifyCore(): headless engine. No React, no slots, no rendering.
 *      It owns event filtering, cooldowns, permissions, Web Audio, IndexedDB,
 *      localStorage, tab leadership, and the toast queue.
 *   2. UI adapters: `settings.section` (configuration), `shell.overlay`
 *      (one-time consent + fallback toasts). They only render state and call
 *      core actions.
 *
 * Hard boundaries: no fetch/XMLHttpRequest/WebSocket/EventSource, no local
 * ports, no IPC, no native app, no bundled fonts/logos/audio.
 */
window.__ModuleLoader__.load({
  id: '@nolit/dsh-notify-web',
  factory: (require) => {
    const React = require('react')
    const exports = {}

    const SETTINGS_KEY = 'dsh-notify-web:settings'
    const CONSENT_KEY = 'dsh-notify-web:consent'
    const LEADER_KEY = 'dsh-notify-web:leader'
    const LEADER_LOCK = 'dsh-notify-web:leader-lock'
    const DB_NAME = 'dsh-notify-web'
    const DB_STORE = 'audio'
    const DB_KEY = 'chime'
    const TOAST_MS = 6000
    const MAX_TOASTS = 3
    const MAX_TITLE = 80
    const MAX_ERROR = 160
    const REQUEST_TTL = 30000
    const MAX_AUDIO_BYTES = 5 * 1024 * 1024
    // Inline 0.12s 880Hz fallback beep. Kept as a data URI so the package still
    // bundles no audio files and the browser can route it through <audio>.
    const FALLBACK_BEEP_DATA_URI = 'data:audio/wav;base64,UklGRqQHAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YYAHAAAAAHgAcAHtARQB3v5K/Or6/fuW/04Ezgf0Bw4Ec/0d90707PZZ/nUH7g1NDsMH2Px18rDtVPFL/OEJwBPmFCoMEP1i7ibnQ+tx+YoLLxmrGzgRHf7x6sHgyuTR9WcMKh6JIuAWAAAx6Jfa/N1x8XMMoSJrKRQdtwIr5rrU6dZa7KgL7CXILiwi4AXi5mvTa9Rr6ckIHiTgLh4kyQhr6WvUa9Pi5uAFLCLILuwlqAsL7JbVmdJz5PECFyCBLpQnfA6/7uzW9dEf4gAA4R0LLhQpQRGE8WzYf9Hp3w/9jRtnLWoq9RNY9BTaONHU3SD6HhmVLJUrlRY39+LbINHi2zf3lRaVK5UsHhkg+tTdONEU2lj09RNqKmctjRsP/enff9Fs2ITxQREUKQsu4R0AAB/i9dHs1r/ufA6UJ4EuFyDxAnPkmdKW1QvsqAvsJcguLCLgBeLma9Nr1GvpyQgeJOAuHiTJCGvpa9Rr0+Lm4AUsIsgu7CWoCwvsltWZ0nPk8QIXIIEulCd8Dr/u7Nb10R/iAADhHQsuFClBEYTxbNh/0enfD/2NG2ctair1E1j0FNo40dTdIPoeGZUslSuVFjf34tsg0eLbN/eVFpUrlSweGSD61N040RTaWPT1E2oqZy2NGw/96d9/0WzYhPFBERQpCy7hHQAAH+L10ezWv+58DpQngS4XIPECc+SZ0pbVC+yoC+wlyC4sIuAF4uZr02vUa+nJCB4k4C4eJMkIa+lr1GvT4ubgBSwiyC7sJagLC+yW1ZnSc+TxAhcggS6UJ3wOv+7s1vXRH+IAAOEdCy4UKUERhPFs2H/R6d8P/Y0bZy1qKvUTWPQU2jjR1N0g+h4ZlSyVK5UWN/fi2yDR4ts395UWlSuVLB4ZIPrU3TjRFNpY9PUTaipnLY0bD/3p33/RbNiE8UERFCkLLuEdAAAf4vXR7Na/7nwOlCeBLhcg8QJz5JnSltUL7KgL7CXILiwi4AXi5mvTa9Rr6ckIHiTgLh4kyQhr6WvUa9Pi5uAFLCLILuwlqAsL7JbVmdJz5PECFyCBLpQnfA6/7uzW9dEf4gAA4R0LLhQpQRGE8WzYf9Hp3w/9jRtnLWoq9RNY9BTaONHU3SD6HhmVLJUrlRY39+LbINHi2zf3lRaVK5UsHhkg+tTdONEU2lj09RNqKmctjRsP/enff9Fs2ITxQREUKQsu4R0AAB/i9dHs1r/ufA6UJ4EuFyDxAnPkmdKW1QvsqAvsJcguLCLgBeLma9Nr1GvpyQgeJOAuHiTJCGvpa9Rr0+Lm4AUsIsgu7CWoCwvsltWZ0nPk8QIXIIEulCd8Dr/u7Nb10R/iAADhHQsuFClBEYTxbNh/0enfD/2NG2ctair1E1j0FNo40dTdIPoeGZUslSuVFjf34tsg0eLbN/eVFpUrlSweGSD61N040RTaWPT1E2oqZy2NGw/96d9/0WzYhPFBERQpCy7hHQAAH+L10ezWv+58DpQngS4XIPECc+SZ0pbVC+yoC+wlyC4sIuAF4uZr02vUa+nJCB4k4C4eJMkIa+lr1GvT4ubgBSwiyC7sJagLC+yW1ZnSc+TxAhcggS6UJ3wOv+7s1vXRH+IAAOEdCy4UKUERhPFs2H/R6d8P/Y0bZy1qKvUTWPQU2jjR1N0g+h4ZlSyVK5UWN/fi2yDR4ts395UWlSuVLB4ZIPrU3TjRFNpY9PUTaipnLY0bD/3p33/RbNiE8UERFCkLLuEdAAAf4vXR7Na/7nwOlCeBLhcg8QJz5JnSltUL7KgL7CXILiwi4AXi5mvTa9Rr6ckIHiTgLh4kyQhr6WvUa9Pi5uAFLCLILuwlqAsL7JbVmdJz5PECFyCBLpQnfA6/7uzW9dEf4gAA4R0LLhQpQRGE8WzYf9Hp3w/9jRtnLWoq9RNY9BTaONHU3SD6HhmVLJUrlRY39+LbINHi2zf3lRaVK5UsHhkg+tTdONEU2lj09RNqKmctjRsP/enff9Fs2ITxQREUKQsu4R0AAB/i9dHs1r/ufA6UJ4EuFyDxAnPkmdKW1QvsqAvsJcguLCLgBeLma9Nr1GvpyQgeJOAuHiTJCGvpa9Rr0+Lm4AUsIsgu7CWoCwvsltWZ0nPk8QIXIIEulCd8Dr/u7Nb10R/iAADhHQsuFClBEYTxbNh/0enfD/2NG2ctair1E1j0FNo40dTdIPoeGZUslSuVFjf34tsg0eLbN/eVFpUrlSweGSD61N040RTaWPT1E2oqZy2NGxX9cuCo0r7ZHvJlEK4m+iqjGwAA3OSP1mDbwvCtDE0i6ydGG3oCCumL2l3d3u9TCQYepSR7GoEE9OyQ3q3fce9eBuIZNCFIGRMGkvCV4kjid+/SA+0VoR20FzAH3PON5iPl7u+xAS8S9xnFFdkHzPZv6jbo0PAAALEOQRaDEw0IXPkx7nbrGPLA/nsLihL3ENEHiPvH8dnuwfPy/ZUI3A4qDicHS/0q9VTyxPWW/QYGQgslCxIGof5Q+N31Gfir/dMDxwfyB5gEif8w+2n5ufow/gMCcwSbBL0CAADC/e78m/0j/5sAUgEqAYkABgA='

    const DEFAULTS = Object.freeze({
      notifyOnComplete: true,
      notifyOnApproval: true,
      notifyOnQuestion: true,
      notifyOnError: true,
      completeCooldownMs: 5000,
      soundEnabled: true,
      volume: 0.3,
      soundSource: 'synth',
      suppressWhenFocused: false,
      requireInteractionForApproval: true,
      notifyOnSubagents: false,
    })

    const TITLES = Object.freeze({
      complete: 'DSH 작업 완료',
      approval: 'DSH 승인 필요',
      question: 'DSH 질문 대기',
      error: 'DSH 오류',
      test: 'DSH 알림 테스트',
    })

    const BODIES = Object.freeze({
      complete: '세션 작업이 끝났습니다. 결과를 확인하세요.',
      approval: '도구 실행 승인을 기다리고 있습니다.',
      question: '모델이 답변을 기다리고 있습니다.',
      error: '모델 요청 또는 도구 실행에서 오류가 발생했습니다.',
      test: '알림과 소리가 정상인지 확인하세요.',
    })

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

    function normalizeSettings(raw) {
      const source = raw && typeof raw === 'object' ? raw : {}
      const out = { ...DEFAULTS }
      for (const key of Object.keys(DEFAULTS)) {
        if (typeof DEFAULTS[key] === 'boolean' && typeof source[key] === 'boolean') {
          out[key] = source[key]
        }
      }
      out.completeCooldownMs = Math.round(clamp(source.completeCooldownMs, 0, 60000))
      out.volume = clamp(source.volume, 0, 0.5)
      out.soundSource = source.soundSource === 'custom' ? 'custom' : 'synth'
      return out
    }

    function createNotifyCore(options = {}) {
      const config = options.config || {}
      const env = options.env || {}
      const sources = options.sources || {}
      const logger = env.logger || console

      const storage = env.storage
      const NotificationCtor = env.Notification
      const AudioCtor = env.AudioContext
      const AudioElementCtor = env.Audio || env.window?.Audio || globalThis.Audio
      const indexedDB = env.indexedDB
      const win = env.window
      const doc = env.document
      const locks = env.locks
      const now = env.now || (() => Date.now())
      const setTimeoutFn = env.setTimeout || setTimeout
      const clearTimeoutFn = env.clearTimeout || clearTimeout
      const setIntervalFn = env.setInterval || setInterval
      const clearIntervalFn = env.clearInterval || clearInterval

      const cooldowns = new Map()
      const requests = new Map()
      const toastTimers = new Map()
      const baseTitle = safe(() => doc?.title || '', '')
      let titleAlert = false
      let autoPermissionRequested = false
      let audioContext = null
      let fallbackAudio = null
      let audioState = 'locked'
      let audioUnlockDispose = null
      let byoBuffer = null
      let byoBytes = null
      let started = false
      let disposers = []

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
        return normalizeSettings({ ...DEFAULTS, ...(config || {}), ...(stored?.settings || stored || {}) })
      }

      function saveSettings(settings) {
        writeJson(SETTINGS_KEY, { version: 1, settings })
      }

      function loadConsent() {
        const value = safe(() => storage?.getItem(CONSENT_KEY), null)
        return value === 'done' || value === 'dismissed' ? value : 'pending'
      }

      // The Notification API is gated on a secure context. Plain HTTP on a LAN
      // address is NOT secure (only localhost/127.0.0.1 and HTTPS are), so a DSH
      // server reached as http://<lan-ip>:3080 can never show an OS notification:
      // Chrome reports `permission === 'denied'` and requestPermission() resolves
      // 'denied' with no prompt, even when a grant exists in site settings.
      // Detect that up front so the UI explains the real cause instead of
      // claiming the user blocked notifications.
      function secureContextOf() {
        return safe(() => globalThis.isSecureContext !== false, true)
      }

      function permissionOf() {
        if (!NotificationCtor) return 'unsupported'
        const reported = NotificationCtor.permission || 'default'
        // Only reinterpret when the insecure context is what actually blocks us:
        // a plain-HTTP LAN origin can never be granted, and Chrome reports that
        // permanent block as 'denied' with no way to prompt.
        if (reported === 'denied' && !secureContextOf()) return 'insecure'
        return reported
      }

      const stateStore = createStore({
        settings: loadSettings(),
        permission: permissionOf(),
        secureContext: secureContextOf(),
        audio: 'locked',
        leader: false,
        consent: loadConsent(),
        toasts: [],
        byoAudio: null,
        lastEventAt: 0,
        lastDelivery: null,
        lastStatusEvent: null,
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

      function setConsent(value) {
        safe(() => storage?.setItem(CONSENT_KEY, value))
        update({ consent: value })
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
        for (const [name, stamp] of requests) {
          if (at - stamp > REQUEST_TTL) requests.delete(name)
        }
        if (requests.has(key)) return true
        requests.set(key, at)
        return false
      }

      function sessionTitle(row) {
        return sanitizeText(row?.displayTitle || row?.title || '', MAX_TITLE)
      }

      function buildBody(kind, row, options) {
        let body = BODIES[kind] || BODIES.error
        if (kind === 'error' && options?.message) body = sanitizeText(options.message, MAX_ERROR)
        if (kind === 'test') body = BODIES.test
        const title = sessionTitle(row)
        return title ? `${body}\n${title}` : body
      }

      function pushToast(kind, title, body) {
        const id = `toast-${now()}-${Math.random().toString(36).slice(2, 7)}`
        const toast = { id, kind, title, body }
        update({ toasts: [...getState().toasts, toast].slice(-MAX_TOASTS) })
        const timer = setTimeoutFn(() => dismissToast(id), TOAST_MS)
        if (timer && typeof timer.unref === 'function') timer.unref()
        toastTimers.set(id, timer)
        return id
      }

      function dismissToast(id) {
        const timer = toastTimers.get(id)
        if (timer) clearTimeoutFn(timer)
        toastTimers.delete(id)
        update({ toasts: getState().toasts.filter((toast) => toast.id !== id) })
      }

      // Chrome can block OS notifications for remote plain-HTTP origins. The
      // tab title is still visible and gives the user a durable cue even when
      // the DSH tab is in the background or the notification banner is denied.
      function markTitleAlert(kind) {
        if (!doc) return
        const label =
          kind === 'complete'
            ? '작업 완료'
            : kind === 'approval'
              ? '승인 필요'
              : kind === 'question'
                ? '질문 대기'
                : kind === 'error'
                  ? '오류'
                  : '알림'
        titleAlert = true
        doc.title = `● ${label} · ${baseTitle}`.slice(0, 240)
      }

      function clearTitleAlert() {
        if (!titleAlert) return
        titleAlert = false
        if (doc && baseTitle) doc.title = baseTitle
      }

      function showOsNotification(kind, sessionId, title, body, settings, nativeSound = false, onFailure) {
        if (!NotificationCtor || NotificationCtor.permission !== 'granted') return false
        try {
          const notification = new NotificationCtor(title, {
            body,
            // A fixed tag makes Windows treat every later test as the same
            // notification and silently drop it. Each instance gets a unique tag.
            tag: `dsh-notify:${kind}:${Date.now()}:${randomId()}`,
            // Completion events have no user gesture. Ask Windows to play its
            // own notification sound even if Web Audio is still locked.
            silent: kind === 'complete' ? false : !nativeSound,
            requireInteraction:
              !!settings.requireInteractionForApproval && (kind === 'approval' || kind === 'question'),
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
          // Return the OS notification slot even when the user ignores it.
          setTimeoutFn(() => safe(() => notification.close()), 4000)
          return true
        } catch {
          return false
        }
      }

      function tone(frequency, at, duration, volume) {
        if (!audioContext) return
        try {
          const oscillator = audioContext.createOscillator()
          const gain = audioContext.createGain()
          oscillator.type = 'sine'
          oscillator.frequency.value = frequency
          gain.gain.setValueAtTime(0.0001, at)
          gain.gain.exponentialRampToValueAtTime(Math.max(0.0001, volume), at + 0.012)
          gain.gain.exponentialRampToValueAtTime(0.0001, at + duration)
          gain.gain.value = volume
          oscillator.connect(gain)
          gain.connect(audioContext.destination)
          oscillator.start(at)
          oscillator.stop(at + duration + 0.02)
          logger?.log?.('[dsh-notify-web] tone scheduled', {
            frequency,
            volume,
            state: audioContext.state,
          })
        } catch (error) {
          logger?.warn?.('[dsh-notify-web] tone failed', error)
        }
      }

      function playBuffer(buffer, volume) {
        if (!audioContext || !buffer) return false
        const source = audioContext.createBufferSource()
        const gain = audioContext.createGain()
        source.buffer = buffer
        gain.gain.value = volume
        source.connect(gain)
        gain.connect(audioContext.destination)
        source.start()
        return true
      }

      function playChime() {
        const settings = getState().settings
        const volume = clamp(settings.volume, 0, 0.5)
        logger?.log?.('[dsh-notify-web] audio play triggered', {
          state: audioContext?.state,
          soundEnabled: settings.soundEnabled,
          soundSource: settings.soundSource,
          volume,
        })
        if (!audioContext || audioContext.state !== 'running') return false
        if (!settings.soundEnabled) return false
        if (volume <= 0) return false
        if (settings.soundSource === 'custom' && byoBuffer) return playBuffer(byoBuffer, volume)
        const start = audioContext.currentTime
        tone(880, start, 0.12, volume)
        tone(1175, start + 0.14, 0.12, volume)
        return true
      }

      function wait(ms) {
        return new Promise((resolve) => {
          try {
            setTimeoutFn(resolve, ms)
          } catch {
            resolve()
          }
        })
      }

      function playFallbackBeep(volume) {
        if (!AudioElementCtor) return false
        try {
          if (fallbackAudio) {
            safe(() => {
              fallbackAudio.pause()
              fallbackAudio.currentTime = 0
              fallbackAudio.src = ''
            })
          }
          // New instance per click; never reuse a completed audio graph.
          const audio = new AudioElementCtor(FALLBACK_BEEP_DATA_URI)
          fallbackAudio = audio
          audio.preload = 'auto'
          audio.volume = clamp(volume, 0.1, 0.5)
          const started = audio.play()
          if (started && typeof started.catch === 'function') {
            started.catch((error) => {
              logger?.warn?.('[dsh-notify-web] fallback <audio> play failed', error)
            })
          }
          logger?.log?.('[dsh-notify-web] fallback <audio> beep', {
            state: audioContext?.state,
            volume: audio.volume,
          })
          return true
        } catch (error) {
          logger?.warn?.('[dsh-notify-web] fallback <audio> failed', error)
          return false
        }
      }

      async function playSynthesizedBeep() {
        // Test-button path: bypass soundEnabled/volume gating. Start the inline
        // <audio> fallback immediately (same click gesture), then try Web Audio.
        const volume = Math.max(0.15, clamp(getState().settings.volume, 0, 0.5))
        playFallbackBeep(Math.min(volume, 0.25))
        if (!AudioCtor) return false
        try {
          if (!audioContext) audioContext = new AudioCtor()
          // Some browsers leave resume() pending indefinitely without a device.
          await Promise.race([audioContext.resume(), wait(1200)])
          audioState = audioContext.state === 'running' ? 'unlocked' : 'locked'
          update({ audio: audioState })
          const start = audioContext.currentTime
          logger?.log?.('[dsh-notify-web] audio play triggered', {
            state: audioContext.state,
            path: 'settings-test',
            volume,
          })
          logger?.log?.('[dsh-notify-web] test beep', { state: audioContext.state, volume })
          if (audioContext.state === 'running') {
            tone(880, start, 0.12, volume)
            tone(1175, start + 0.14, 0.12, volume)
          }
          return true
        } catch (error) {
          logger?.warn?.('[dsh-notify-web] test beep failed', error)
          return false
        }
      }

      function installAudioUnlock() {
        const target = win || globalThis
        const unlock = () => {
          if (!AudioCtor) return
          try {
            if (!audioContext) audioContext = new AudioCtor()
            if (audioContext.state === 'running') return
            audioContext.resume().then(() => {
              audioState = audioContext.state === 'running' ? 'unlocked' : 'locked'
              update({ audio: audioState })
              logger?.log?.('[dsh-notify-web] audio unlocked by gesture', {
                state: audioContext.state,
              })
            }).catch((error) => {
              logger?.warn?.('[dsh-notify-web] gesture audio unlock failed', error)
            })
          } catch (error) {
            logger?.warn?.('[dsh-notify-web] gesture audio init failed', error)
          }
        }
        target.addEventListener?.('pointerdown', unlock, { passive: true })
        target.addEventListener?.('keydown', unlock)
        return () => {
          target.removeEventListener?.('pointerdown', unlock)
          target.removeEventListener?.('keydown', unlock)
        }
      }

      async function ensureAudio() {
        if (!AudioCtor) {
          audioState = 'unsupported'
          update({ audio: audioState })
          return audioState
        }
        if (!audioContext) {
          try {
            audioContext = new AudioCtor()
          } catch {
            audioState = 'unsupported'
            update({ audio: audioState })
            return audioState
          }
        }
        try {
          // Chrome may report 'suspended' or 'interrupted'; always try resume inside
          // the click/test gesture before scheduling any oscillator.
          if (audioContext.state !== 'running') {
            logger?.log?.('[dsh-notify-web] audio resume', { state: audioContext.state })
            await audioContext.resume()
          }
          logger?.log?.('[dsh-notify-web] audio state after resume', { state: audioContext.state })
          audioState = audioContext.state === 'running' ? 'unlocked' : 'locked'
          if (
            audioState === 'unlocked' &&
            getState().settings.soundSource === 'custom' &&
            !byoBuffer &&
            byoBytes
          ) {
            try {
              byoBuffer = await audioContext.decodeAudioData(byoBytes.slice(0))
            } catch {
              byoBuffer = null
              byoBytes = null
            }
          }
        } catch (error) {
          logger?.warn?.('[dsh-notify-web] audio resume failed', error)
          audioState = 'locked'
        }
        update({ audio: audioState })
        return audioState
      }

      async function requestNotifications() {
        if (!NotificationCtor || typeof NotificationCtor.requestPermission !== 'function') {
          update({ permission: 'unsupported' })
          return 'unsupported'
        }
        try {
          await NotificationCtor.requestPermission()
        } catch {
          // Browser policies may reject without a gesture; state below is authoritative.
        }
        const permission = permissionOf()
        update({ permission })
        if (permission === 'granted' && getState().consent === 'pending') setConsent('done')
        return permission
      }

      function openDb() {
        return new Promise((resolve, reject) => {
          if (!indexedDB || typeof indexedDB.open !== 'function') {
            reject(new Error('IndexedDB unavailable'))
            return
          }
          const request = indexedDB.open(DB_NAME, 1)
          request.onupgradeneeded = () => {
            const db = request.result
            if (!db.objectStoreNames.contains(DB_STORE)) db.createObjectStore(DB_STORE)
          }
          request.onsuccess = () => resolve(request.result)
          request.onerror = () => reject(request.error || new Error('IndexedDB open failed'))
        })
      }

      async function idbPut(value) {
        const db = await openDb()
        try {
          await new Promise((resolve, reject) => {
            const tx = db.transaction(DB_STORE, 'readwrite')
            tx.objectStore(DB_STORE).put(value, DB_KEY)
            tx.oncomplete = () => resolve()
            tx.onerror = () => reject(tx.error || new Error('IndexedDB write failed'))
          })
        } finally {
          db.close()
        }
      }

      async function idbGet() {
        const db = await openDb()
        try {
          return await new Promise((resolve, reject) => {
            const tx = db.transaction(DB_STORE, 'readonly')
            const request = tx.objectStore(DB_STORE).get(DB_KEY)
            request.onsuccess = () => resolve(request.result)
            request.onerror = () => reject(request.error || new Error('IndexedDB read failed'))
          })
        } finally {
          db.close()
        }
      }

      async function idbDelete() {
        const db = await openDb()
        try {
          await new Promise((resolve, reject) => {
            const tx = db.transaction(DB_STORE, 'readwrite')
            tx.objectStore(DB_STORE).delete(DB_KEY)
            tx.oncomplete = () => resolve()
            tx.onerror = () => reject(tx.error || new Error('IndexedDB delete failed'))
          })
        } finally {
          db.close()
        }
      }

      async function loadByoAudio() {
        const meta = readJson('dsh-notify-web:audio', null)
        if (!meta) return
        update({ byoAudio: meta })
        try {
          const stored = await idbGet()
          if (stored && stored.bytes) byoBytes = stored.bytes
        } catch {
          // Session-only fallback; metadata remains visible.
        }
      }

      async function setByoAudio(file) {
        if (!file || typeof file.arrayBuffer !== 'function') throw new Error('오디오 파일이 아닙니다.')
        if (file.size > MAX_AUDIO_BYTES) throw new Error('오디오 파일은 5MB 이하만 지원합니다.')
        if (file.type && !String(file.type).startsWith('audio/')) throw new Error('오디오 파일만 선택할 수 있습니다.')
        const state = await ensureAudio()
        if (state === 'unsupported') throw new Error('이 브라우저는 Web Audio를 지원하지 않습니다.')
        const bytes = await file.arrayBuffer()
        let buffer = null
        try {
          buffer = await audioContext.decodeAudioData(bytes.slice(0))
        } catch {
          throw new Error('오디오 파일을 디코드할 수 없습니다.')
        }
        byoBytes = bytes
        byoBuffer = buffer
        const meta = {
          name: sanitizeText(file.name || 'custom-audio', 80),
          size: file.size || bytes.byteLength,
          type: file.type || 'audio/*',
          persisted: false,
        }
        try {
          await idbPut({ bytes, meta })
          meta.persisted = true
        } catch {
          // Session-only BYO audio; the settings page explains the fallback.
        }
        writeJson('dsh-notify-web:audio', meta)
        update({ byoAudio: meta })
        updateSettings({ ...getState().settings, soundSource: 'custom' })
        return meta
      }

      async function clearByoAudio() {
        byoBuffer = null
        byoBytes = null
        safe(() => localStorageRemove('dsh-notify-web:audio'))
        try {
          await idbDelete()
        } catch {
          // Nothing persisted.
        }
        update({ byoAudio: null })
        updateSettings({ ...getState().settings, soundSource: 'synth' })
      }

      function localStorageRemove(key) {
        storage?.removeItem(key)
      }

      // Hermes-style convenience: the first real event may ask Chrome for
      // permission once per page if the user has not answered yet. Browsers
      // may still require a gesture; the in-app toast and title alert below
      // are the guaranteed fallback.
      function autoRequestPermission() {
        if (autoPermissionRequested) return false
        if (!NotificationCtor || typeof NotificationCtor.requestPermission !== 'function') return false
        autoPermissionRequested = true
        Promise.resolve(NotificationCtor.requestPermission())
          .then(() => {
            const permission = permissionOf()
            update({ permission })
            if (permission === 'granted' && getState().consent === 'pending') setConsent('done')
          })
          .catch((error) => logger?.warn?.('[dsh-notify-web] permission request failed', error))
        return true
      }

      function emit(kind, sessionId, options = {}) {
        if (!started && !options.force) return false
        const focused = safe(() => doc?.hasFocus?.(), false)
        // A focused tab must notify even if a stale lease from an older tab
        // still owns leader election. The leader remains the background fallback.
        if (!options.force && !getState().leader && !focused) return false
        const settings = getState().settings
        if (!options.force && !enabledFor(kind, settings)) return false

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

        const title = TITLES[kind] || TITLES.error
        const body = buildBody(kind, row, options)
        const osAllowed = !(kind === 'complete' && settings.suppressWhenFocused && focused)
        const permission = permissionOf()
        if (permission !== getState().permission) update({ permission })

        let osShown = false
        let fallbackToastId = null
        const showFallback = () => {
          if (fallbackToastId !== null) return
          fallbackToastId = pushToast(kind, title, body)
          markTitleAlert(kind)
          update({ lastDelivery: { ...getState().lastDelivery, osShown: false, toastId: fallbackToastId } })
        }
        if (osAllowed && permission === 'granted') {
          osShown = showOsNotification(
            kind,
            sessionId,
            title,
            body,
            settings,
            options.nativeSound === true,
            showFallback,
          )
        }

        // Preferred visual channel: the OS notification when Chrome permits and
        // accepts it. The in-app toast and tab-title marker are fallback only,
        // so a working Chrome notification does not produce a duplicate toast.
        if (!osShown) showFallback()
        const toastId = osShown ? null : fallbackToastId
        if (!osShown && osAllowed && permission === 'default') autoRequestPermission()
        if (settings.soundEnabled && !options.skipSound) playChime()
        const at = now()
        update({
          lastEventAt: at,
          lastDelivery: {
            kind,
            sessionId: sessionId ?? null,
            permission,
            osAllowed,
            osShown,
            toastId,
            at,
          },
        })
        return osShown
      }

      function handleStatus(sessionId, running) {
        try {
          const at = now()
          update({ lastStatusEvent: { sessionId: sessionId ?? null, running, at } })
          logger?.log?.('[dsh-notify-web] status event', {
            sessionId,
            running,
            leader: getState().leader,
            focused: safe(() => doc?.hasFocus?.(), false),
          })
          if (running) {
            cooldowns.delete(`complete:${sessionId}`)
            return
          }
          emit('complete', sessionId)
        } catch (error) {
          logger?.warn?.('[dsh-notify-web] status handler failed', error)
        }
      }

      function handleError(sessionId, message) {
        try {
          emit('error', sessionId, { message })
        } catch (error) {
          logger?.warn?.('[dsh-notify-web] error handler failed', error)
        }
      }

      function handleApproval(scope, request, next) {
        try {
          const sessionId = safe(() => sources.scopeOf?.(scope), undefined) || request?.sessionId
          const key = request?.callId || request?.id || request?.requestId
          if (!recentRequest(key ? `approval:${key}` : '')) emit('approval', sessionId, { request })
        } catch (error) {
          logger?.warn?.('[dsh-notify-web] approval handler failed', error)
        }
        return next()
      }

      function handleQuestion(scope, request, next) {
        try {
          const sessionId = safe(() => sources.scopeOf?.(scope), undefined) || request?.sessionId
          const key = request?.callId || request?.id || request?.requestId
          if (!recentRequest(key ? `question:${key}` : '')) emit('question', sessionId, { request })
        } catch (error) {
          logger?.warn?.('[dsh-notify-web] question handler failed', error)
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
        const permission = permissionOf()
        const audio = audioContext?.state === 'running' ? 'unlocked' : audioState
        update({ permission, secureContext: secureContextOf(), audio, leader: leader.isLeader() })
        if (permission === 'granted' && getState().consent === 'pending') setConsent('done')
        if (safe(() => doc?.visibilityState === 'visible', false) && safe(() => doc?.hasFocus?.(), false)) {
          clearTitleAlert()
        }
      }

      function onStorage(event) {
        if (!event || event.key === SETTINGS_KEY || event.key === null) {
          update({ settings: loadSettings() })
        }
        if (!event || event.key === CONSENT_KEY || event.key === null) {
          update({ consent: loadConsent() })
        }
      }

      function start() {
        if (started) return
        started = true
        loadByoAudio()
        audioUnlockDispose = installAudioUnlock()
        leader.start()
        const bind = (source, handler) => {
          try {
            return typeof source === 'function' ? source(handler) : undefined
          } catch (error) {
            logger?.warn?.('[dsh-notify-web] subscription failed', error)
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
        win?.addEventListener?.('storage', onStorage)
        win?.addEventListener?.('focus', refresh)
        refresh()
      }

      function stop() {
        if (!started) return
        started = false
        for (const dispose of disposers.splice(0)) safe(dispose)
        if (audioUnlockDispose) {
          safe(audioUnlockDispose)
          audioUnlockDispose = null
        }
        leader.stop()
        win?.removeEventListener?.('storage', onStorage)
        win?.removeEventListener?.('focus', refresh)
        clearTitleAlert()
        for (const timer of toastTimers.values()) clearTimeoutFn(timer)
        toastTimers.clear()
        if (audioContext) {
          safe(() => audioContext.close())
          audioContext = null
        }
        audioState = 'locked'
        update({ audio: audioState })
      }

      const core = {
        start,
        stop,
        refresh,
        getState,
        subscribe,
        actions: {
          requestNotifications,
          enableSound: async () => {
            const state = await ensureAudio()
            if (state === 'unlocked') playChime()
            return state
          },
          test: async () => {
            // Directly wired from Settings → 테스트 알림. No soundEnabled gate.
            // Bound the resume attempt so a stuck AudioContext cannot hold busy=true.
            await Promise.race([playSynthesizedBeep(), wait(1500)])
            return emit('test', 'test', { force: true, skipSound: true, nativeSound: true })
          },
          setSetting(key, value) {
            return updateSettings({ ...getState().settings, [key]: value })
          },
          resetSettings() {
            const settings = normalizeSettings({ ...DEFAULTS, ...(config || {}) })
            saveSettings(settings)
            update({ settings })
            return settings
          },
          setByoAudio,
          clearByoAudio,
          dismissConsent(value = 'dismissed') {
            setConsent(value)
          },
          dismissToast,
        },
        __handlers: { handleStatus, handleError, handleApproval, handleQuestion },
      }
      return core
    }

    // ---------------------------------------------------------------------
    // UI adapters
    // ---------------------------------------------------------------------

    function useCoreState(core) {
      const [state, setState] = React.useState(() => core.getState())
      React.useEffect(() => core.subscribe(setState), [core])
      return state
    }

    const styles = {
      section: {
        padding: '4px 2px 24px',
        color: 'var(--dsw-alias-label-primary, #f5f5f5)',
        fontFamily: 'var(--ds-font-family, "Segoe UI", system-ui, sans-serif)',
        fontSize: 13,
        lineHeight: 1.5,
      },
      card: {
        border: '1px solid var(--dsw-alias-border-l2, #3a3a3a)',
        borderRadius: 12,
        padding: 14,
        marginTop: 10,
        background: 'var(--dsw-alias-bg-layer-2, #1f1f1f)',
      },
      title: {
        fontSize: 14,
        fontWeight: 600,
        marginBottom: 6,
      },
      muted: {
        color: 'var(--dsw-alias-label-tertiary, #9ca3af)',
        fontSize: 12,
        lineHeight: 1.45,
      },
      row: {
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        marginTop: 8,
      },
      grow: {
        flex: 1,
        minWidth: 0,
      },
      button: {
        border: '1px solid var(--dsw-alias-border-l2, #3a3a3a)',
        borderRadius: 8,
        background: 'var(--dsw-alias-interactive-bg-hover, #2a2a2a)',
        color: 'inherit',
        cursor: 'pointer',
        padding: '6px 9px',
        font: 'inherit',
      },
      primary: {
        border: '1px solid var(--dsw-alias-state-business-primary, #4d6bfe)',
        borderRadius: 8,
        background: 'var(--dsw-alias-state-business-primary, #4d6bfe)',
        color: '#fff',
        cursor: 'pointer',
        padding: '6px 9px',
        font: 'inherit',
      },
      input: {
        color: 'inherit',
        font: 'inherit',
      },
      badge: {
        display: 'inline-flex',
        alignItems: 'center',
        gap: 6,
        color: 'var(--dsw-alias-label-secondary, #c9c9c9)',
        fontSize: 12,
      },
      dot: {
        width: 8,
        height: 8,
        borderRadius: 999,
        flex: 'none',
      },
      overlay: {
        position: 'absolute',
        right: 16,
        bottom: 16,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'flex-end',
        gap: 8,
        maxWidth: 'calc(100vw - 32px)',
        pointerEvents: 'none',
      },
      toast: {
        width: 320,
        maxWidth: 'calc(100vw - 32px)',
        padding: '10px 12px',
        borderRadius: 10,
        border: '1px solid var(--dsw-alias-border-l2, #3a3a3a)',
        background: 'var(--dsw-alias-bg-layer-2, #1f1f1f)',
        color: 'var(--dsw-alias-label-primary, #f5f5f5)',
        boxShadow: '0 10px 28px rgba(0,0,0,.35)',
        pointerEvents: 'auto',
        fontSize: 12,
      },
    }

    function statusDot(state) {
      if (state.permission === 'granted' && state.audio === 'unlocked') return '#4ade80'
      if (state.permission === 'default') return '#fbbf24'
      return '#9ca3af'
    }

    function statusLabel(state) {
      if (state.permission === 'insecure') return '보안 컨텍스트 아님 (https/localhost 필요)'
      if (state.permission === 'unsupported') return '알림 미지원'
      if (state.permission === 'denied') return '알림 차단됨'
      if (state.permission === 'granted') return '알림 켜짐'
      return '알림 설정 필요'
    }

    // Native settings panel styling: one stylesheet, class-based, DSH tokens only.
    // Mirrors the shipped settings sections (title + description rows with a
    // right-aligned control, .5px separators, --dsw-radius-* corners) instead of
    // inline pixel styling, so it inherits theme, density and dark/light modes.
    const NOTIFY_CSS = [
      '.dshNbxSection{display:grid;gap:16px;padding:16px 0;min-width:0;font-size:14px;line-height:22px;color:var(--dsw-alias-label-primary)}',
      '.dshNbxHeading{margin:0;color:var(--dsw-alias-label-primary);font-size:14px;font-weight:500;line-height:22px}',
      '.dshNbxHint{margin:0;color:var(--dsw-alias-label-tertiary);font-size:12px;line-height:1.5}',
      '.dshNbxCard{border:.5px solid var(--dsw-alias-border-l3);border-radius:var(--dsw-radius-lg);display:grid;min-width:0}',
      '.dshNbxCardHead{display:flex;align-items:baseline;justify-content:space-between;gap:12px;padding:14px 14px 0;min-width:0}',
      '.dshNbxCardTitle{margin:0;color:var(--dsw-alias-label-primary);font-size:14px;font-weight:500;line-height:22px}',
      '.dshNbxMeta{color:var(--dsw-alias-label-tertiary);font-size:12px;line-height:18px;text-align:right;min-width:0}',
      '.dshNbxRows{padding:0 14px 6px;min-width:0}',
      '.dshNbxRow{display:flex;align-items:center;justify-content:space-between;gap:24px;padding:12px 0;border-bottom:.5px solid var(--dsw-alias-border-l2);min-width:0}',
      '.dshNbxRow:last-child{border-bottom:0}',
      '.dshNbxRowText{min-width:0}',
      '.dshNbxTitle{color:var(--dsw-alias-label-primary);font-size:14px;line-height:22px}',
      '.dshNbxDesc{margin-top:4px;color:var(--dsw-alias-label-secondary);font-size:12px;line-height:18px}',
      '.dshNbxControl{display:flex;align-items:center;gap:8px;flex:0 0 auto}',
      '.dshNbxSwitch{appearance:none;background:var(--dsw-alias-interactive-bg-active);border:.5px solid var(--dsw-alias-border-l4);border-radius:999px;cursor:pointer;height:20px;margin:0;position:relative;transition:background .15s ease,border-color .15s ease;width:36px;flex:0 0 auto}',
      '.dshNbxSwitch::after{background:var(--dsw-alias-label-primary);border-radius:999px;content:"";height:14px;left:2px;position:absolute;top:2px;transition:transform .15s ease,background .15s ease;width:14px}',
      '.dshNbxSwitch:checked{background:var(--dsw-alias-button-primary-fill);border-color:var(--dsw-alias-button-primary-fill)}',
      '.dshNbxSwitch:checked::after{background:var(--dsw-alias-label-primary-foreground);transform:translateX(16px)}',
      '.dshNbxSwitch:disabled{cursor:default;opacity:.55}',
      '.dshNbxSwitch:focus-visible{outline:2px solid var(--dsw-alias-brand-primary);outline-offset:2px}',
      '.dshNbxInput{background:var(--dsw-alias-bg-layer-1);border:.5px solid var(--dsw-alias-border-l4);border-radius:var(--dsw-radius-md);color:var(--dsw-alias-label-primary);font:inherit;font-size:13px;line-height:20px;padding:4px 8px;min-width:0}',
      '.dshNbxInput:focus-visible{outline:2px solid var(--dsw-alias-brand-primary);outline-offset:1px}',
      '.dshNbxSelect{appearance:none;background:var(--dsw-alias-bg-layer-3);border:.5px solid var(--dsw-alias-border-l4);border-radius:var(--dsw-radius-md);color:var(--dsw-alias-label-primary);cursor:pointer;font:inherit;font-size:13px;line-height:20px;padding:4px 10px}',
      '.dshNbxActions{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:0 14px 14px}',
      '.dshNbxButton{appearance:none;background:var(--dsw-alias-bg-layer-3);border:.5px solid var(--dsw-alias-border-l4);border-radius:var(--dsw-radius-md);color:var(--dsw-alias-label-primary);cursor:pointer;font:inherit;font-size:13px;line-height:20px;padding:4px 12px}',
      '.dshNbxButton:hover:not(:disabled){border-color:var(--dsw-alias-border-l3)}',
      '.dshNbxButton:disabled{cursor:default;opacity:.55}',
      '.dshNbxButton:focus-visible{outline:2px solid var(--dsw-alias-brand-primary);outline-offset:1px}',
      '.dshNbxPrimary{background:var(--dsw-alias-button-primary-fill);border-color:var(--dsw-alias-button-primary-fill);color:var(--dsw-alias-label-primary-foreground)}',
      '.dshNbxLabel{display:inline-flex;align-items:center;gap:6px;cursor:pointer;font:inherit;font-size:13px}',
      '.dshNbxStatus{display:flex;align-items:center;gap:8px;padding:0 14px 12px;min-width:0}',
      '.dshNbxDot{border-radius:999px;flex:0 0 auto;height:8px;width:8px}',
      '.dshNbxNotice{margin:0;color:var(--dsw-alias-label-secondary);font-size:12px;line-height:1.5}',
      '.dshNbxError{margin:0;color:var(--dsw-alias-state-error-primary);font-size:12px;line-height:1.5}',
      '.dshNbxList{display:grid;gap:2px;padding:0 14px 10px}',
      '.dshNbxListItem{color:var(--dsw-alias-label-tertiary);font-size:12px;line-height:1.5;overflow-wrap:anywhere}',
    ].join('')

    /** Inject the section stylesheet once per document. */
    function ensureNotifyStyles() {
      if (typeof document === 'undefined' || !document.head) return
      const tagId = '@nolit/dsh-notify-web/notifications.css'
      if (document.querySelector('style[data-plugin-css="' + tagId + '"]') !== null) return
      const tag = document.createElement('style')
      tag.dataset.plugin = '@nolit/dsh-notify-web'
      tag.dataset.pluginCss = tagId
      tag.textContent = NOTIFY_CSS
      document.head.appendChild(tag)
    }

    function makeSettingsSection(core) {
      return function NotificationsSettings() {
        const state = useCoreState(core)
        const [message, setMessage] = React.useState('')
        const [busy, setBusy] = React.useState(false)

        ensureNotifyStyles()

        async function run(operation, lockMs = 1500) {
          setBusy(true)
          setMessage('')
          // Watchdog: even if a browser audio promise never settles, the next
          // click must be accepted within one second.
          const unlock = setTimeout(() => setBusy(false), Math.min(lockMs, 1000))
          try {
            const result = await operation()
            if (typeof result === 'string') setMessage(result)
          } catch (error) {
            setMessage(error instanceof Error ? error.message : String(error))
          } finally {
            clearTimeout(unlock)
            setBusy(false)
          }
        }

        function onTest() {
          return run(async () => {
            await core.actions.test()
            return '테스트 알림을 보냈습니다.'
          }, 1000)
        }

        async function onFile(event) {
          const file = event.target.files?.[0]
          event.target.value = ''
          if (!file) return
          await run(async () => {
            const meta = await core.actions.setByoAudio(file)
            return meta?.persisted
              ? '사용자 오디오를 저장했습니다.'
              : '이 브라우저에서는 세션 동안만 사용됩니다.'
          })
        }

        const settings = state.settings
        const h = React.createElement

        /** A native-style row: title + description on the left, control on the right. */
        function row(key, title, description, control) {
          return h(
            'div',
            { key, className: 'dshNbxRow' },
            h(
              'div',
              { className: 'dshNbxRowText' },
              h('div', { className: 'dshNbxTitle' }, title),
              description ? h('div', { className: 'dshNbxDesc' }, description) : null,
            ),
            h('div', { className: 'dshNbxControl' }, control),
          )
        }

        function toggle(key, title, description) {
          return row(
            key,
            title,
            description,
            h('input', {
              type: 'checkbox',
              className: 'dshNbxSwitch',
              role: 'switch',
              'aria-label': title,
              checked: !!settings[key],
              onChange: (event) => core.actions.setSetting(key, event.target.checked),
            }),
          )
        }

        function card(key, title, meta, children) {
          return h(
            'section',
            { key, className: 'dshNbxCard' },
            h(
              'div',
              { className: 'dshNbxCardHead' },
              h('h3', { className: 'dshNbxCardTitle' }, title),
              meta ? h('span', { className: 'dshNbxMeta' }, meta) : null,
            ),
            h('div', { className: 'dshNbxRows' }, children),
          )
        }

        return h(
          'div',
          { className: 'dshNbxSection' },
          h(
            'div',
            null,
            h('h2', { className: 'dshNbxHeading' }, 'DSH 알림'),
            h(
              'p',
              { className: 'dshNbxHint' },
              'DSH 탭이 열려 있을 때만 동작합니다. 브라우저 알림 권한과 소리를 여기서 설정합니다.',
            ),
          ),
          card(
            'status',
            '연결 상태',
            state.leader ? '이 탭: 담당' : '이 탭: 대기',
            [
              h(
                'div',
                { key: 'status', className: 'dshNbxStatus' },
                h('span', { className: 'dshNbxDot', style: { background: statusDot(state) } }),
                h('span', { className: 'dshNbxNotice' }, statusLabel(state)),
              ),
            ].concat(
              message
                ? [h('p', { key: 'message', className: 'dshNbxNotice', style: { padding: '0 14px 12px' } }, message)]
                : [],
            ),
          ),
          h(
            'section',
            { key: 'actions', className: 'dshNbxCard' },
            h('div', { className: 'dshNbxCardHead' }, h('h3', { className: 'dshNbxCardTitle' }, '권한과 소리')),
            h(
              'div',
              { className: 'dshNbxActions' },
              h(
                'button',
                {
                  type: 'button',
                  className: 'dshNbxButton dshNbxPrimary',
                  disabled:
                    busy ||
                    state.permission === 'unsupported' ||
                    state.permission === 'insecure' ||
                    state.permission === 'denied',
                  onClick: () =>
                    run(async () => {
                      if (state.permission === 'insecure') {
                        return '보안 컨텍스트가 아니어서 OS 알림을 켤 수 없습니다. https 또는 localhost로 접속하세요. (지금은 화면 토스트와 소리로 알립니다.)'
                      }
                      const permission = await core.actions.requestNotifications()
                      if (permission === 'granted') return '브라우저 알림이 켜졌습니다.'
                      return '브라우저 알림이 허용되지 않았습니다.'
                    }),
                },
                '브라우저 알림 켜기',
              ),
              h(
                'button',
                {
                  type: 'button',
                  className: 'dshNbxButton',
                  disabled: busy || state.audio === 'unsupported',
                  onClick: () =>
                    run(async () => {
                      const audio = await core.actions.enableSound()
                      return audio === 'unlocked' ? '소리가 켜졌습니다.' : '브라우저가 소리를 막고 있습니다.'
                    }),
                },
                '소리 켜기',
              ),
              h(
                'button',
                { type: 'button', className: 'dshNbxButton', disabled: busy, onClick: onTest },
                '테스트 알림',
              ),
            ),
          ),
          card('kinds', '알림 종류', null, [
            toggle('notifyOnComplete', '턴 완료', '에이전트가 답변을 마쳤을 때'),
            toggle('notifyOnApproval', '도구 승인 필요', '도구 실행 승인을 기다릴 때'),
            toggle('notifyOnQuestion', '질문 대기', '에이전트가 질문에 답을 기다릴 때'),
            toggle('notifyOnError', '오류', '턴이 오류로 끝났을 때'),
            toggle('notifyOnSubagents', '서브에이전트 완료도 알림', '하위 에이전트가 끝났을 때도 알립니다'),
            toggle('suppressWhenFocused', '창이 활성일 때 완료 알림 숨김', '보고 있는 중에는 방해하지 않습니다'),
            row(
              'cooldown',
              '완료 알림 쿨다운',
              '같은 세션의 완료 알림을 묶는 시간(초)',
              h('input', {
                type: 'number',
                min: 0,
                max: 60,
                step: 1,
                className: 'dshNbxInput',
                style: { width: 72 },
                'aria-label': '완료 알림 쿨다운(초)',
                value: Math.round(settings.completeCooldownMs / 1000),
                onChange: (event) =>
                  core.actions.setSetting('completeCooldownMs', clamp(Number(event.target.value), 0, 60) * 1000),
              }),
            ),
          ]),
          card('sound', '소리', null, [
            toggle('soundEnabled', '알림 소리 사용', '알림이 표시될 때 소리를 재생합니다'),
            row(
              'source',
              '소리 소스',
              '기본 합성음 또는 직접 고른 오디오',
              h(
                'select',
                {
                  className: 'dshNbxSelect',
                  'aria-label': '소리 소스',
                  value: settings.soundSource,
                  onChange: (event) => core.actions.setSetting('soundSource', event.target.value),
                },
                h('option', { value: 'synth' }, '기본 합성음'),
                h('option', { value: 'custom' }, '사용자 오디오'),
              ),
            ),
            row(
              'file',
              '오디오 파일',
              state.byoAudio
                ? state.byoAudio.name +
                  ' · ' +
                  Math.ceil((state.byoAudio.size || 0) / 1024) +
                  'KB' +
                  (state.byoAudio.persisted ? ' · 저장됨' : ' · 세션 한정')
                : '기본값은 Web Audio 합성음입니다. 사용자가 선택한 오디오의 라이선스 책임은 사용자에게 있습니다.',
              h(
                'div',
                { style: { display: 'flex', gap: 8, alignItems: 'center' } },
                h(
                  'label',
                  { className: 'dshNbxLabel dshNbxButton' },
                  '오디오 파일 선택',
                  h('input', { type: 'file', accept: 'audio/*', style: { display: 'none' }, onChange: onFile }),
                ),
                h(
                  'button',
                  {
                    type: 'button',
                    className: 'dshNbxButton',
                    disabled: busy || !state.byoAudio,
                    onClick: () =>
                      run(async () => {
                        await core.actions.clearByoAudio()
                        return '사용자 오디오를 제거했습니다.'
                      }),
                  },
                  '초기화',
                ),
              ),
            ),
            row(
              'volume',
              '볼륨',
              '알림 소리의 크기',
              h('input', {
                type: 'range',
                min: 0,
                max: 0.5,
                step: 0.05,
                'aria-label': '볼륨',
                value: settings.volume,
                onChange: (event) => core.actions.setSetting('volume', Number(event.target.value)),
              }),
            ),
          ]),
          h(
            'section',
            { key: 'info', className: 'dshNbxCard' },
            h(
              'div',
              { className: 'dshNbxCardHead' },
              h('h3', { className: 'dshNbxCardTitle' }, '진단 정보'),
              h('span', { className: 'dshNbxMeta' }, 'MIT 라이선스 · 번들 폰트/로고/오디오 없음'),
            ),
            h(
              'div',
              { className: 'dshNbxList' },
              h('span', { className: 'dshNbxListItem' }, '권한: ' + state.permission + ' · 오디오: ' + state.audio),
              h('span', { className: 'dshNbxListItem' }, '출처: ' + safe(() => location.origin, '')),
              h('span', { className: 'dshNbxListItem' }, '보안 컨텍스트: ' + (state.secureContext ? '예' : '아니오')),
              h(
                'span',
                { className: 'dshNbxListItem' },
                state.lastStatusEvent
                  ? '최근 상태 이벤트: ' +
                      state.lastStatusEvent.sessionId +
                      ' · ' +
                      (state.lastStatusEvent.running ? '실행 중' : '완료')
                  : '최근 상태 이벤트: 없음',
              ),
              h(
                'span',
                { className: 'dshNbxListItem' },
                state.lastDelivery
                  ? '최근 알림: ' +
                      state.lastDelivery.kind +
                      ' · OS ' +
                      (state.lastDelivery.osShown ? '시도' : '미시도') +
                      ' · 화면 토스트 표시'
                  : '최근 알림: 없음',
              ),
              h(
                'p',
                { className: 'dshNbxListItem' },
                state.secureContext
                  ? 'Chrome OS 알림이 허용되어 표시되면 화면 토스트는 생략됩니다. 차단되었거나 표시할 수 없을 때만 토스트와 탭 제목으로 폴백합니다.'
                  : '원격 HTTP 접속은 보안 컨텍스트가 아니어서 Chrome이 OS 알림을 차단합니다. HTTPS 또는 localhost 터널을 사용하세요. 차단 중에는 화면 토스트·소리·탭 제목으로 폴백합니다.',
              ),
            ),
            h(
              'div',
              { className: 'dshNbxActions' },
              h(
                'button',
                {
                  type: 'button',
                  className: 'dshNbxButton',
                  onClick: () => {
                    core.actions.resetSettings()
                    setMessage('설정을 기본값으로 되돌렸습니다.')
                  },
                },
                '설정 초기화',
              ),
              h(
                'button',
                {
                  type: 'button',
                  className: 'dshNbxButton',
                  onClick: () => {
                    core.actions.dismissConsent('pending')
                    setMessage('첫 사용 안내를 다시 표시합니다.')
                  },
                },
                '첫 사용 안내 다시 보기',
              ),
            ),
          ),
        )
      }
    }

    function makeOverlay(core) {
      return function NotificationsOverlay() {
        const state = useCoreState(core)
        const showConsent =
          state.consent === 'pending' && state.permission === 'default' && state.audio !== 'unsupported'
        const [busy, setBusy] = React.useState(false)

        async function enable() {
          setBusy(true)
          try {
            const permission = await core.actions.requestNotifications()
            if (permission === 'granted') {
              await core.actions.enableSound()
              core.actions.dismissConsent('done')
            } else {
              core.actions.dismissConsent('dismissed')
            }
          } finally {
            setBusy(false)
          }
        }

        return React.createElement(
          'div',
          { style: styles.overlay },
          showConsent
            ? React.createElement(
                'div',
                {
                  role: 'dialog',
                  'aria-modal': 'false',
                  'aria-label': 'DSH 알림 설정',
                  style: { ...styles.toast, width: 360 },
                },
                React.createElement('div', { style: styles.title }, 'DSH 알림을 켜시겠습니까?'),
                React.createElement(
                  'div',
                  { style: styles.muted },
                  '브라우저 알림과 소리로 턴 완료·승인·질문을 알려드립니다. 설정은 Settings > 알림에서 언제든 변경할 수 있습니다.',
                ),
                React.createElement(
                  'div',
                  { style: { ...styles.row, justifyContent: 'flex-end' } },
                  React.createElement(
                    'button',
                    {
                      type: 'button',
                      style: styles.button,
                      disabled: busy,
                      onClick: () => core.actions.dismissConsent('dismissed'),
                    },
                    '나중에',
                  ),
                  React.createElement(
                    'button',
                    { type: 'button', style: styles.primary, disabled: busy, onClick: enable },
                    '알림 켜기',
                  ),
                ),
              )
            : null,
          ...state.toasts.map((toast) =>
            React.createElement(
              'div',
              { key: toast.id, role: 'status', 'aria-live': 'polite', style: styles.toast },
              React.createElement(
                'div',
                { style: { display: 'flex', gap: 8, alignItems: 'start' } },
                React.createElement(
                  'div',
                  { style: { flex: 1, minWidth: 0 } },
                  React.createElement('div', { style: { fontWeight: 600 } }, toast.title),
                  React.createElement(
                    'div',
                    { style: { marginTop: 3, opacity: 0.82, whiteSpace: 'pre-wrap' } },
                    toast.body,
                  ),
                ),
                React.createElement(
                  'button',
                  {
                    type: 'button',
                    'aria-label': '닫기',
                    onClick: () => core.actions.dismissToast(toast.id),
                    style: {
                      border: 'none',
                      background: 'transparent',
                      color: 'inherit',
                      cursor: 'pointer',
                      opacity: 0.65,
                      padding: 0,
                      font: 'inherit',
                    },
                  },
                  '×',
                ),
              ),
            ),
          ),
        )
      }
    }

    function apply(ctx, config = {}) {
      const env = {
        storage: safe(() => window.localStorage, undefined),
        Notification: safe(() => window.Notification, undefined),
        AudioContext: safe(() => window.AudioContext || window.webkitAudioContext, undefined),
        indexedDB: safe(() => window.indexedDB, undefined),
        window,
        document,
        locks: safe(() => navigator.locks, undefined),
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
      const Overlay = makeOverlay(core)
      const cleanups = []

      function effect(fn, label) {
        try {
          const dispose = ctx.effect ? ctx.effect(fn, label) : fn()
          if (typeof dispose === 'function') cleanups.push(dispose)
        } catch (error) {
          env.logger?.warn?.(`[dsh-notify-web] effect failed: ${label}`, error)
        }
      }

      core.start()

      effect(
        () =>
          ctx.slots.inject('settings.section', () =>
            ctx.slots.register(
              {
                name: 'settings.section',
                id: 'notifications',
                // Below the agent-preset section (order 20) and above the
                // OpenCode v2 section (order 60): the nav is core sections
                // first, then plugin sections in ascending order.
                order: 50,
                // The label follows the UI locale: Korean shows 알림, every
                // other locale shows Notifications (measured 2026-10-31: the
                // hardcoded Korean label leaked into the English UI).
                label: () => {
                  let active = ''
                  try {
                    active = String(ctx?.locale?.getSnapshot?.()?.active ?? '')
                  } catch {
                    /* locale service unavailable: fall back to the browser */
                  }
                  if (active.length === 0 && typeof navigator !== 'undefined') {
                    active = String(navigator.language ?? '')
                  }
                  return /^ko/i.test(active) ? '알림' : 'Notifications'
                },
              },
              SettingsSection,
            ),
          ),
        'dsh-notify-web: settings',
      )

      effect(
        () =>
          ctx.slots.inject('shell.overlay', () =>
            ctx.slots.register(
              {
                name: 'shell.overlay',
                id: 'dsh-notify-web.overlay',
              },
              Overlay,
            ),
          ),
        'dsh-notify-web: overlay',
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

      globalThis.__dshNotifyWeb = { core, dispose }
      return dispose
    }

    exports.apply = apply
    exports.inject = ['remote', 'sessions', 'slots', 'locale']
    exports.__test = {
      createNotifyCore,
      defaults: DEFAULTS,
      normalizeSettings,
      sanitizeText,
    }

    return exports
  },
})
