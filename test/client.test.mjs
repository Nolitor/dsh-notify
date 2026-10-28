import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'

const source = readFileSync(new URL('../lib/client.js', import.meta.url), 'utf8')

function createStorage(initial = {}) {
  const map = new Map(Object.entries(initial))
  return {
    getItem(key) {
      return map.has(key) ? map.get(key) : null
    },
    setItem(key, value) {
      map.set(key, String(value))
    },
    removeItem(key) {
      map.delete(key)
    },
  }
}

function createIndexedDb() {
  const rows = new Map()
  return {
    rows,
    open() {
      const request = { result: null, error: null, onupgradeneeded: null, onsuccess: null, onerror: null }
      queueMicrotask(() => {
        const db = {
          objectStoreNames: { contains: () => true },
          createObjectStore() {},
          close() {},
          transaction() {
            const tx = { oncomplete: null, onerror: null }
            tx.objectStore = () => ({
              put(value, key) {
                rows.set(key, value)
                queueMicrotask(() => tx.oncomplete?.())
              },
              get(key) {
                const get = { result: rows.get(key), onsuccess: null, onerror: null }
                queueMicrotask(() => get.onsuccess?.())
                return get
              },
              delete(key) {
                rows.delete(key)
                queueMicrotask(() => tx.oncomplete?.())
              },
            })
            return tx
          },
        }
        request.result = db
        request.onupgradeneeded?.()
        request.onsuccess?.()
      })
      return request
    },
  }
}

function createHarness({ permission = 'granted', rows = {}, config = {}, indexedDB = createIndexedDb() } = {}) {
  const notifications = []
  const audioStarts = []
  const bufferStarts = []
  let loaded = null

  class FakeNotification {
    constructor(title, options) {
      this.title = title
      this.options = options
      this.closed = false
      notifications.push(this)
    }

    close() {
      this.closed = true
    }
  }
  FakeNotification.permission = permission
  FakeNotification.requestPermission = async () => permission

  class FakeAudioContext {
    constructor() {
      this.state = 'running'
      this.currentTime = 1
      this.destination = {}
    }

    createOscillator() {
      const oscillator = {
        type: 'sine',
        frequency: { value: 0 },
        connect() {},
        start() {
          audioStarts.push(oscillator.frequency.value)
        },
        stop() {},
      }
      return oscillator
    }

    createBufferSource() {
      const source = {
        buffer: null,
        connect() {},
        start() {
          bufferStarts.push(source.buffer)
        },
      }
      return source
    }

    createGain() {
      return {
        gain: {
          value: 0,
          setValueAtTime() {},
          exponentialRampToValueAtTime() {},
        },
        connect() {},
      }
    }

    async decodeAudioData() {
      return { duration: 0.2, kind: 'decoded' }
    }

    resume() {
      this.state = 'running'
      return Promise.resolve()
    }

    close() {
      this.state = 'closed'
      return Promise.resolve()
    }
  }

  const storage = createStorage()
  const document = {
    hasFocus: () => false,
    visibilityState: 'visible',
    addEventListener() {},
    removeEventListener() {},
  }
  const window = {
    __ModuleLoader__: {
      load(definition) {
        loaded = definition
      },
    },
    localStorage: storage,
    crypto: { randomUUID: () => `test-${Math.random().toString(36).slice(2)}` },
    Notification: FakeNotification,
    AudioContext: FakeAudioContext,
    indexedDB,
    focus() {},
    addEventListener() {},
    removeEventListener() {},
  }

  const sandbox = {
    window,
    document,
    navigator: {},
    localStorage: storage,
    crypto: window.crypto,
    Notification: FakeNotification,
    AudioContext: FakeAudioContext,
    indexedDB,
    setTimeout: () => 0,
    clearTimeout() {},
    setInterval: () => 0,
    clearInterval() {},
    console,
    Date,
    Math,
    JSON,
    Promise,
  }
  vm.createContext(sandbox)
  vm.runInContext(source, sandbox)

  const React = {
    createElement(type, props, ...children) {
      return { type, props, children }
    },
    useState(initial) {
      return [typeof initial === 'function' ? initial() : initial, () => {}]
    },
    useEffect() {},
  }

  const module = loaded.factory((name) => {
    if (name === 'react') return React
    throw new Error(`unexpected require: ${name}`)
  })

  const handlers = {}
  const components = {}
  const effects = []
  const ctx = {
    remote: {
      $on(event, handler) {
        handlers[event] = handler
        return () => {
          delete handlers[event]
        }
      },
    },
    sessions: {
      list: {
        getSnapshot() {
          return { byId: rows }
        },
      },
      scopeOf(scope) {
        return scope?.sessionId
      },
    },
    slots: {
      inject(_name, factory) {
        return factory()
      },
      register(definition, component) {
        const key = `${definition.name}:${definition.id}`
        components[key] = component
        return () => {
          delete components[key]
        }
      },
    },
    effect(fn, label) {
      const dispose = fn()
      if (typeof dispose === 'function') effects.push(dispose)
      return dispose
    },
    logger: { warn() {}, info() {}, debug() {} },
  }

  const dispose = module.apply(ctx, config)
  const core = sandbox.__dshNotifyWeb.core

  return {
    module,
    core,
    ctx,
    handlers,
    components,
    effects,
    notifications,
    audioStarts,
    bufferStarts,
    storage,
    indexedDB,
    sandbox,
    dispose,
  }
}

function createCoreHarness({ permission = 'granted', rows = {}, indexedDB = createIndexedDb(), audioState = 'running', audioElement = false, isSecureContext = true } = {}) {
  const notifications = []
  const audioStarts = []
  const resumeCalls = []
  const fallbackStarts = []
  class FakeAudioElement {
    constructor(src) {
      this.src = src
      this.volume = 1
      this.preload = ''
      fallbackStarts.push(src)
    }
    play() {
      return Promise.resolve()
    }
    pause() {}
  }
  class FakeNotification {
    constructor(title, options) {
      this.title = title
      this.options = options
      notifications.push(this)
    }
    close() {}
  }
  FakeNotification.permission = permission
  FakeNotification.requestPermission = async () => permission

  class FakeAudioContext {
    constructor() {
      this.state = audioState
      this.currentTime = 1
      this.destination = {}
    }
    createOscillator() {
      const oscillator = {
        type: 'sine',
        frequency: { value: 0 },
        connect() {},
        start() {
          audioStarts.push(oscillator.frequency.value)
        },
        stop() {},
      }
      return oscillator
    }
    createGain() {
      return { gain: { value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {} }
    }
    createBufferSource() {
      return { buffer: null, connect() {}, start() {} }
    }
    async decodeAudioData() {
      return { duration: 0.2 }
    }
    resume() {
      resumeCalls.push(this.state)
      this.state = 'running'
      return Promise.resolve()
    }
    close() {
      return Promise.resolve()
    }
  }

  const storage = createStorage()
  const handlers = {}
  const window = {
    localStorage: storage,
    addEventListener() {},
    removeEventListener() {},
  }
  const document = { hasFocus: () => false, addEventListener() {}, removeEventListener() {} }

  const bundle = createHarness({ permission, rows, indexedDB })
  // `isSecureContext` is a global in browsers, not a core-harness env member.
  // Set it on the vm sandbox the module was evaluated in so secureContextOf()
  // reads the value the test intends.
  if (typeof isSecureContext === 'boolean') bundle.sandbox.isSecureContext = isSecureContext
  const core = bundle.module.__test.createNotifyCore({
    config: {},
    env: {
      storage,
      Notification: FakeNotification,
      AudioContext: FakeAudioContext,
      Audio: audioElement ? FakeAudioElement : undefined,
      indexedDB,
      window,
      document,
      locks: undefined,
      now: () => 1000,
      setTimeout: () => 0,
      clearTimeout() {},
      setInterval: () => 0,
      clearInterval() {},
      logger: { log() {}, warn() {} },
    },
    sources: {
      status(handler) {
        handlers.status = handler
        return () => {}
      },
      error(handler) {
        handlers.error = handler
        return () => {}
      },
      approval(handler) {
        handlers.approval = handler
        return () => {}
      },
      question(handler) {
        handlers.question = handler
        return () => {}
      },
      session(id) {
        return rows[id]
      },
      scopeOf(scope) {
        return scope?.sessionId
      },
    },
  })
  core.start()
  return { core, handlers, notifications, storage, indexedDB, audioStarts, resumeCalls, fallbackStarts }
}

test('settings.section and shell.overlay are registered; sidebar footer is not', () => {
  const harness = createHarness()
  assert.ok(harness.components['settings.section:notifications'])
  assert.ok(harness.components['shell.overlay:dsh-notify-web.overlay'])
  assert.ok(!Object.keys(harness.components).some((key) => key.startsWith('sidebar.footer.action')))
  harness.dispose()
})

test('test action resumes a suspended AudioContext before playing the chime', async () => {
  const harness = createCoreHarness({ audioState: 'suspended' })
  await harness.core.actions.test()
  assert.deepEqual(harness.resumeCalls, ['suspended'])
  assert.equal(harness.core.getState().audio, 'unlocked')
  assert.equal(harness.audioStarts.length, 2)
  assert.equal(harness.notifications.length, 1)
  harness.core.stop()
})

test('test action plays the beep even when soundEnabled is off', async () => {
  const harness = createCoreHarness({ audioState: 'suspended' })
  harness.core.actions.setSetting('soundEnabled', false)
  await harness.core.actions.test()
  assert.equal(harness.audioStarts.length, 2)
  harness.core.stop()
})

test('test action starts the inline <audio> fallback in the same gesture', async () => {
  const harness = createCoreHarness({ audioState: 'suspended', audioElement: true })
  await harness.core.actions.test()
  assert.equal(harness.fallbackStarts.length, 1)
  assert.ok(harness.fallbackStarts[0].startsWith('data:audio/wav;base64,'))
  assert.equal(harness.notifications[0].options.silent, false)
  harness.core.stop()
})

test('test action remains repeatable across three clicks', async () => {
  const harness = createCoreHarness({ audioState: 'suspended', audioElement: true })
  for (let index = 0; index < 3; index += 1) {
    await harness.core.actions.test()
  }
  assert.equal(harness.notifications.length, 3)
  assert.equal(harness.audioStarts.length, 6)
  assert.equal(harness.fallbackStarts.length, 3)
  assert.equal(new Set(harness.notifications.map((item) => item.options.tag)).size, 3)
  harness.core.stop()
})

test('headless core completes once per cooldown', () => {
  const harness = createCoreHarness({ rows: { s1: { id: 's1' } } })
  harness.handlers.status('s1', false)
  harness.handlers.status('s1', false)
  assert.equal(harness.notifications.length, 1)
  assert.equal(harness.notifications[0].options.silent, false)
  harness.core.stop()
})

test('headless core skips subagent completion by default', () => {
  const harness = createCoreHarness({
    rows: { child: { id: 'child', parentId: 'root', origin: 'subagent' } },
  })
  harness.handlers.status('child', false)
  assert.equal(harness.notifications.length, 0)
  harness.core.stop()
})

test('headless core truncates error messages', () => {
  const harness = createCoreHarness({ rows: { s1: { id: 's1' } } })
  harness.handlers.error('s1', 'x'.repeat(300))
  assert.equal(harness.notifications.length, 1)
  assert.equal(harness.notifications[0].title, 'DSH 오류')
  assert.ok(harness.notifications[0].options.body.includes('x'.repeat(160)))
  assert.ok(!harness.notifications[0].options.body.includes('x'.repeat(161)))
  harness.core.stop()
})

test('headless core approval passes next exactly once', () => {
  const harness = createCoreHarness()
  let nextCalls = 0
  harness.handlers.approval.call({ sessionId: 's1' }, { callId: 'a-1' }, () => {
    nextCalls += 1
  })
  assert.equal(nextCalls, 1)
  assert.equal(harness.notifications.length, 1)
  assert.equal(harness.notifications[0].title, 'DSH 승인 필요')
  harness.core.stop()
})

test('headless core question passes next exactly once', () => {
  const harness = createCoreHarness()
  let nextCalls = 0
  harness.handlers.question.call({ sessionId: 's1' }, { callId: 'q-1' }, () => {
    nextCalls += 1
  })
  assert.equal(nextCalls, 1)
  assert.equal(harness.notifications.length, 1)
  assert.equal(harness.notifications[0].title, 'DSH 질문 대기')
  harness.core.stop()
})

test('headless core falls back to a toast when permission is denied', () => {
  const harness = createCoreHarness({ permission: 'denied', rows: { s1: { id: 's1' } } })
  harness.handlers.status('s1', false)
  assert.equal(harness.notifications.length, 0)
  assert.equal(harness.core.getState().toasts.length, 1)
  harness.core.stop()
})

test('headless core persists settings in localStorage', () => {
  const harness = createCoreHarness()
  harness.core.actions.setSetting('notifyOnComplete', false)
  const stored = JSON.parse(harness.storage.getItem('dsh-notify-web:settings'))
  assert.equal(stored.settings.notifyOnComplete, false)
  harness.core.stop()
})

test('BYO audio decodes and persists metadata', async () => {
  const harness = createCoreHarness()
  const file = {
    name: 'custom.wav',
    size: 4,
    type: 'audio/wav',
    async arrayBuffer() {
      return new Uint8Array([1, 2, 3, 4]).buffer
    },
  }
  const meta = await harness.core.actions.setByoAudio(file)
  assert.equal(meta.persisted, true)
  assert.equal(harness.core.getState().settings.soundSource, 'custom')
  assert.equal(harness.core.getState().byoAudio.name, 'custom.wav')
  assert.ok(harness.indexedDB.rows.has('chime'))
  harness.core.stop()
})

test('BYO audio clears back to synth', async () => {
  const harness = createCoreHarness()
  await harness.core.actions.setByoAudio({
    name: 'custom.wav',
    size: 4,
    type: 'audio/wav',
    async arrayBuffer() {
      return new Uint8Array([1, 2, 3, 4]).buffer
    },
  })
  await harness.core.actions.clearByoAudio()
  assert.equal(harness.core.getState().settings.soundSource, 'synth')
  assert.equal(harness.core.getState().byoAudio, null)
  assert.ok(!harness.indexedDB.rows.has('chime'))
  harness.core.stop()
})

test('apply wires event handlers and cleanup removes them', () => {
  const harness = createHarness({ rows: { s1: { id: 's1' } } })
  assert.ok(harness.handlers['api-session/status'])
  harness.dispose()
  assert.equal(harness.handlers['api-session/status'], undefined)
})

// --- 0.2.2-alpha.2 regression coverage ------------------------------------

test('injected package names match the 0.2.2-alpha.2 client graph', () => {
  // `@deepseek-ai/dsh-client-ui-slots` never existed: the `slots` service is
  // owned by dsh-client-ui-renderer (which every core slot consumer injects).
  // An unresolvable inject is silently dropped by client-modules, so the
  // package still boots but loses its guaranteed ordering after renderer.
  const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'))
  const inject = pkg.dsh.client.inject
  assert.ok(!inject.includes('@deepseek-ai/dsh-client-ui-slots'))
  assert.ok(inject.includes('@deepseek-ai/dsh-client-ui-renderer'))
  assert.ok(inject.includes('@deepseek-ai/dsh-api-remotes'))
})

test('insecure context reports permission as insecure, not denied', () => {
  // Plain HTTP on a LAN address is not a secure context: Chrome pins
  // Notification.permission to 'denied' with no prompt possible.
  const harness = createCoreHarness({ permission: 'denied', isSecureContext: false })
  assert.equal(harness.core.getState().permission, 'insecure')
  assert.equal(harness.core.getState().secureContext, false)
  // Degrades to a toast instead of silently dropping the notification.
  harness.handlers.status('s1', false)
  assert.equal(harness.core.getState().toasts.length, 1)
  assert.equal(harness.notifications.length, 0)
  harness.core.stop()
})

test('secure context keeps the real denied state', () => {
  const harness = createCoreHarness({ permission: 'denied', isSecureContext: true })
  assert.equal(harness.core.getState().permission, 'denied')
  harness.core.stop()
})

test('granted permission fires an OS notification without a duplicate in-app toast', () => {
  const harness = createCoreHarness({ permission: 'granted', isSecureContext: true })
  harness.handlers.status('s1', false)
  assert.equal(harness.notifications.length, 1)
  assert.equal(harness.core.getState().toasts.length, 0)
  assert.equal(harness.core.getState().lastDelivery.kind, 'complete')
  assert.equal(harness.core.getState().lastDelivery.osShown, true)
  harness.core.stop()
})
