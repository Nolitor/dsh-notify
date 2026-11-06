/**
 * Notify for Chrome — browser-half tests.
 *
 * The plugin has exactly one notification channel: the Chrome / Web
 * Notification API. When Chrome cannot show it, the DSH toast is the silent
 * fallback. There is no audio engine, no BYO audio, no IndexedDB and no
 * self-authored stylesheet; those removals are asserted here as well as in the
 * typography contract.
 */
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'

const source = readFileSync(new URL('../lib/client.js', import.meta.url), 'utf8')

function createStorage(initial = {}) {
  const map = new Map(Object.entries(initial))
  return {
    map,
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

function makePrimitives() {
  const primitives = {}
  for (const name of ['Button', 'Input', 'Switch', 'Tag', 'Toast', 'IconAlarmClockOutlineRegular']) {
    const Primitive = function Primitive(props) {
      return { __primitive: name, props: props ?? {} }
    }
    Primitive.__primitiveName = name
    primitives[name] = Primitive
  }
  return primitives
}

function loadModule({ isSecureContext = true } = {}) {
  let loaded = null
  const sandbox = {
    window: { __ModuleLoader__: { load(definition) { loaded = definition } } },
    document: { hasFocus: () => false, addEventListener() {}, removeEventListener() {} },
    navigator: {},
    console: { log() {}, warn() {} },
    Date,
    Math,
    JSON,
    Promise,
    setTimeout: () => 0,
    clearTimeout() {},
    setInterval: () => 0,
    clearInterval() {},
  }
  if (typeof isSecureContext === 'boolean') sandbox.isSecureContext = isSecureContext
  vm.createContext(sandbox)
  vm.runInContext(source, sandbox)
  const primitives = makePrimitives()
  const React = {
    createElement(type, props, ...children) {
      return { type, props: props ?? {}, children }
    },
    useState(initial) {
      return [typeof initial === 'function' ? initial() : initial, () => {}]
    },
    useEffect() {},
  }
  const module = loaded.factory((name) => {
    if (name === 'react') return React
    if (name === '@deepseek-ai/dsh-client-ui-primitives') return primitives
    throw new Error('unexpected require: ' + name)
  })
  return { module, sandbox, React, primitives }
}

const PLATFORM_DATASET = {
  windows: 'win32',
  macos: 'darwin',
  linux: 'linux',
  other: '',
}

function makeApplyHarness(options = {}) {
  const {
    permission = 'granted',
    platform = 'linux',
    installState = 'browser',
    locale = 'en',
    isSecureContext = true,
    throwOnConstruct = false,
  } = options

  const { module, sandbox } = loadModule({ isSecureContext })
  const storage = createStorage()
  const notifications = []
  const nextCalls = { approval: 0, question: 0 }

  class FakeNotification {
    constructor(title, options) {
      if (throwOnConstruct) throw new Error('notification constructor refused')
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

  const document = {
    hasFocus: () => false,
    addEventListener() {},
    removeEventListener() {},
    documentElement: { dataset: { platform: PLATFORM_DATASET[platform] ?? '' } },
  }
  const matchMedia = (query) => ({ matches: installState === 'installed' && query.includes('display-mode') })
  const navigator = {
    userAgentData: { platform: platform === 'windows' ? 'Windows' : platform },
    locks: undefined,
  }
  sandbox.window.localStorage = storage
  sandbox.window.Notification = FakeNotification
  sandbox.window.navigator = navigator
  sandbox.window.matchMedia = matchMedia
  sandbox.window.addEventListener = () => {}
  sandbox.window.removeEventListener = () => {}
  sandbox.document = document
  sandbox.navigator = navigator

  const handlers = {}
  const components = {}
  const effects = []
  const localeState = { active: locale }
  const localeListeners = new Set()
  const rows = options.rows ?? {}

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
    locale: {
      getSnapshot() {
        return { active: localeState.active }
      },
      subscribe(listener) {
        localeListeners.add(listener)
        return () => localeListeners.delete(listener)
      },
    },
    effect(fn, label) {
      const dispose = fn()
      if (typeof dispose === 'function') effects.push(dispose)
      return dispose
    },
    logger: { log() {}, warn() {} },
  }

  const dispose = module.apply(ctx, {})
  const core = sandbox.__dshNotifyChrome.core

  function setLocale(next) {
    localeState.active = next
    for (const listener of [...localeListeners]) listener()
  }

  return {
    module,
    sandbox,
    ctx,
    core,
    components,
    handlers,
    notifications,
    storage,
    localeListeners,
    setLocale,
    effects,
    nextCalls,
    document,
    dispose,
  }
}

function flatten(node, out = []) {
  if (node === null || node === undefined || node === false || node === true) return out
  if (Array.isArray(node)) {
    for (const child of node) flatten(child, out)
    return out
  }
  if (typeof node !== 'object') return out
  // React.createElement of a native primitive keeps the component as `type`;
  // materialize it so tests can assert the native primitive that would render.
  if (typeof node.type === 'function' && typeof node.type.__primitiveName === 'string') {
    out.push({ __primitive: node.type.__primitiveName, props: node.props ?? {}, children: node.children })
    return out
  }
  out.push(node)
  if (Array.isArray(node.children)) for (const child of node.children) flatten(child, out)
  return out
}

function emitStatus(harness, sessionId = 's1') {
  harness.handlers['api-session/status'](sessionId, false)
}

function emitApproval(harness, key = 'a-1', scope = { sessionId: 's1' }) {
  harness.handlers['approval/request'].call(scope, { callId: key }, () => {
    harness.nextCalls.approval += 1
  })
}

function emitQuestion(harness, key = 'q-1', scope = { sessionId: 's1' }) {
  harness.handlers['user-questions/request'].call(scope, { callId: key }, () => {
    harness.nextCalls.question += 1
  })
}

// --- registration and activation contract --------------------------------

test('registers the native settings section, its DSH icon and the toast overlay', () => {
  const harness = makeApplyHarness()
  assert.ok(harness.components['settings.section:notifications'], 'settings section must register')
  assert.ok(harness.components['settings.section.icon:notifications'], 'native settings icon must register')
  assert.ok(harness.components['shell.overlay:dsh-notify-web.toast'], 'fallback toast overlay must register')
  assert.equal(
    Object.keys(harness.components).some((key) => key.startsWith('sidebar.footer.action')),
    false,
    'no sidebar footer surface',
  )
  harness.dispose()
})

test('exported inject covers every ctx service apply() reads', () => {
  const harness = makeApplyHarness()
  const inject = harness.module.inject
  for (const service of ['remote', 'sessions', 'slots', 'locale']) {
    assert.ok(inject.includes(service), 'inject must declare ' + service)
  }
  const applyBody = source.slice(source.indexOf('function apply('), source.indexOf('exports.apply'))
  const used = new Set([...applyBody.matchAll(/ctx\.([A-Za-z_$][\w$]*)/g)].map((match) => match[1]))
  for (const service of ['remote', 'sessions', 'slots', 'locale']) {
    assert.ok(used.has(service), 'apply() still reads ctx.' + service + '; keep it in inject')
  }
  harness.dispose()
})

// --- Chrome notification primary path -------------------------------------

test('granted permission sends a Chrome notification and no toast', () => {
  const harness = makeApplyHarness({ permission: 'granted' })
  emitStatus(harness)
  assert.equal(harness.notifications.length, 1)
  assert.equal(harness.notifications[0].options.silent, false, 'the OS notification owns the sound')
  assert.ok(String(harness.notifications[0].options.tag).startsWith('dsh-notify:complete:'))
  assert.equal(harness.core.getState().fallbackToast, null)
  assert.equal(harness.core.getState().lastDelivery.osShown, true)
  assert.equal(harness.core.getState().lastDelivery.fallback, false)
  harness.dispose()
})

test('every event gets a unique tag so Windows cannot replace and drop it', async () => {
  const harness = makeApplyHarness({ permission: 'granted' })
  await harness.core.actions.test()
  await harness.core.actions.test()
  await harness.core.actions.test()
  assert.equal(harness.notifications.length, 3)
  const tags = harness.notifications.map((item) => item.options.tag)
  assert.equal(new Set(tags).size, 3, 'tags must be unique per event')
  for (const tag of tags) assert.ok(String(tag).includes('dsh-notify:test:'))
  harness.dispose()
})

test('test action reports the channel it actually used', async () => {
  const ok = makeApplyHarness({ permission: 'granted' })
  assert.equal(await ok.core.actions.test(), 'chrome')
  ok.dispose()
  const blocked = makeApplyHarness({ permission: 'denied' })
  assert.equal(await blocked.core.actions.test(), 'fallback')
  blocked.dispose()
})

// --- silent toast fallback -------------------------------------------------

test('denied permission falls back to the silent in-app toast', () => {
  const harness = makeApplyHarness({ permission: 'denied' })
  emitStatus(harness)
  assert.equal(harness.notifications.length, 0, 'Chrome path must not fire')
  const toast = harness.core.getState().fallbackToast
  assert.ok(toast, 'a fallback toast record is required')
  assert.equal(toast.kind, 'complete')
  assert.equal(harness.core.getState().lastDelivery.fallback, true)
  assert.equal(harness.core.getState().lastDelivery.osShown, false)
  harness.dispose()
})

test('insecure context reports "insecure" and falls back to the toast', () => {
  const harness = makeApplyHarness({ permission: 'denied', isSecureContext: false })
  assert.equal(harness.core.getState().permission, 'insecure')
  assert.equal(harness.core.getState().secureContext, false)
  emitStatus(harness)
  assert.equal(harness.notifications.length, 0)
  assert.ok(harness.core.getState().fallbackToast)
  harness.dispose()
})

test('a refused Notification constructor falls back instead of throwing', () => {
  const harness = makeApplyHarness({ permission: 'granted', throwOnConstruct: true })
  emitStatus(harness)
  assert.equal(harness.notifications.length, 0)
  const toast = harness.core.getState().fallbackToast
  assert.ok(toast, 'constructor failure must produce the toast fallback')
  assert.equal(harness.core.getState().lastDelivery.osShown, false)
  harness.dispose()
})

test('the overlay renders the native DSH Toast only when the fallback is active', () => {
  const harness = makeApplyHarness({ permission: 'denied' })
  const Overlay = harness.components['shell.overlay:dsh-notify-web.toast']
  assert.equal(Overlay({}), null, 'no toast while nothing failed')
  emitStatus(harness)
  const tree = Overlay({})
  assert.ok(tree, 'fallback toast must render')
  assert.equal(tree.type?.__primitiveName, 'Toast', 'it must be the native DSH Toast, not a custom node')
  assert.ok(String(tree.props.text).includes('Turn complete'))
  assert.equal(typeof tree.props.onDone, 'function')
  harness.dispose()
})

// --- Windows / install-environment branch ---------------------------------

test('Windows installed app keeps every Chrome notification open', () => {
  const harness = makeApplyHarness({ platform: 'windows', installState: 'installed' })
  emitStatus(harness)
  assert.equal(harness.notifications[0].options.requireInteraction, true, 'completion stays until dismissed')
  emitApproval(harness)
  assert.equal(harness.notifications[1].options.requireInteraction, true)
  harness.dispose()
})

test('Windows browser tab keeps only approval/question notifications open', () => {
  const harness = makeApplyHarness({ platform: 'windows', installState: 'browser' })
  emitStatus(harness)
  assert.equal(harness.notifications[0].options.requireInteraction, false)
  emitApproval(harness)
  assert.equal(harness.notifications[1].options.requireInteraction, true)
  assert.equal(harness.notifications[1].options.silent, false)
  harness.dispose()
})

test('macOS never asks for requireInteraction (Chrome does not honour it)', () => {
  const harness = makeApplyHarness({ platform: 'macos' })
  emitApproval(harness)
  assert.equal(harness.notifications[0].options.requireInteraction, false)
  harness.dispose()
})

test('Linux honours the approval interaction setting', () => {
  const harness = makeApplyHarness({ platform: 'linux' })
  emitApproval(harness)
  assert.equal(harness.notifications[0].options.requireInteraction, true)
  harness.core.actions.setSetting('requireInteractionForApproval', false)
  emitQuestion(harness, 'q-2')
  assert.equal(harness.notifications[1].options.requireInteraction, false)
  harness.dispose()
})

test('the environment is detected from the DSH platform dataset and display mode', () => {
  const detect = makeApplyHarness({ platform: 'windows' }).module.__test.detectEnvironment
  assert.deepEqual(
    { ...detect({ document: { documentElement: { dataset: { platform: 'win32' } } }, navigator: {} }) },
    { platform: 'windows', installState: 'browser', browser: 'other' },
  )
  assert.equal(detect({ document: {}, navigator: { userAgentData: { platform: 'macOS' } } }).platform, 'macos')
  assert.equal(detect({ document: {}, navigator: { userAgent: 'Mozilla/5.0 (X11; Linux x86_64)' } }).platform, 'linux')
  assert.equal(
    detect({ document: {}, navigator: {}, matchMedia: (query) => ({ matches: query.includes('standalone') }) }).installState,
    'installed',
  )
})

test('the engine family is reported so the UI never implies unsupported browsers work', () => {
  // Read the detector from a plain module load: makeApplyHarness() installs its
  // own navigator stub (platform, no userAgent), which would shadow the UAs below.
  const detect = loadModule().module.__test.detectEnvironment
  const chrome = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36'
  assert.equal(detect({ document: {}, navigator: { userAgent: chrome } }).browser, 'chromium')
  // Real Edge/Opera UAs keep the Chrome/ token and append their own; they do not
  // replace it. Fixtures must match that or the test proves nothing.
  assert.equal(
    detect({ document: {}, navigator: { userAgent: `${chrome} Edg/156.0.0.0` } }).browser,
    'chromium',
    'Edge is Chromium',
  )
  assert.equal(
    detect({ document: {}, navigator: { userAgent: `${chrome} OPR/120.0.0.0` } }).browser,
    'chromium',
    'Opera is Chromium',
  )
  // Brave hides the extra token behind navigator.brave but still sends Chrome/.
  assert.equal(
    detect({ document: {}, navigator: { userAgent: chrome, brave: { isBrave: async () => true } } }).browser,
    'chromium',
    'Brave is Chromium',
  )
  assert.equal(
    detect({ document: {}, navigator: { userAgent: 'Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0' } }).browser,
    'firefox',
  )
  assert.equal(
    detect({ document: {}, navigator: { userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/17.0 Safari/605.1.15', vendor: 'Apple Computer, Inc.' } }).browser,
    'safari',
  )
  assert.equal(detect({ document: {}, navigator: {} }).browser, 'other')
})

// --- behaviour -------------------------------------------------------------

test('completion cooldown groups repeated events for one session', () => {
  const harness = makeApplyHarness({ permission: 'granted' })
  emitStatus(harness, 's1')
  emitStatus(harness, 's1')
  assert.equal(harness.notifications.length, 1)
  harness.dispose()
})

test('subagent completion is skipped unless enabled', () => {
  const rows = { child: { id: 'child', parentId: 'root', origin: 'subagent' } }
  const harness = makeApplyHarness({ permission: 'granted', rows })
  emitStatus(harness, 'child')
  assert.equal(harness.notifications.length, 0)
  harness.core.actions.setSetting('notifyOnSubagents', true)
  emitStatus(harness, 'child')
  assert.equal(harness.notifications.length, 1)
  harness.dispose()
})

test('error messages are truncated to 160 characters', () => {
  const harness = makeApplyHarness({ permission: 'granted' })
  harness.handlers['api-session/error']('s1', 'x'.repeat(300))
  assert.equal(harness.notifications.length, 1)
  assert.equal(harness.notifications[0].title, 'Turn failed')
  assert.ok(harness.notifications[0].options.body.includes('x'.repeat(160)))
  assert.ok(!harness.notifications[0].options.body.includes('x'.repeat(161)))
  harness.dispose()
})

test('approval and question notifications still pass next exactly once', () => {
  const harness = makeApplyHarness({ permission: 'granted' })
  emitApproval(harness, 'a-1')
  emitApproval(harness, 'a-1')
  assert.equal(harness.nextCalls.approval, 2, 'next is always called')
  assert.equal(harness.notifications.filter((item) => item.title === 'Approval needed').length, 1, 'duplicate call id deduplicated')
  emitQuestion(harness, 'q-1')
  assert.equal(harness.nextCalls.question, 1)
  assert.equal(harness.notifications.at(-1).title, 'Question waiting')
  harness.dispose()
})

test('settings persist in localStorage under the plugin key without removed audio keys', () => {
  const harness = makeApplyHarness()
  harness.core.actions.setSetting('notifyOnComplete', false)
  const stored = JSON.parse(harness.storage.getItem('dsh-notify-web:settings'))
  assert.equal(stored.version, 2)
  assert.equal(stored.settings.notifyOnComplete, false)
  for (const removed of ['soundEnabled', 'soundSource', 'volume']) {
    assert.equal(removed in stored.settings, false, removed + ' must not be persisted')
  }
  harness.dispose()
})

// --- locale ----------------------------------------------------------------

test('English is the default and Korean is used only for a Korean host locale', () => {
  const english = makeApplyHarness({ permission: 'granted', locale: 'en-US' })
  emitStatus(english)
  assert.equal(english.notifications[0].title, 'Turn complete')
  english.dispose()

  const korean = makeApplyHarness({ permission: 'granted', locale: 'ko-KR' })
  emitStatus(korean)
  assert.equal(korean.notifications[0].title, '턴 완료')
  korean.dispose()
})

test('a live locale switch changes the next notification language', () => {
  const harness = makeApplyHarness({ permission: 'granted', locale: 'en' })
  emitStatus(harness)
  assert.equal(harness.core.getState().lang, 'en')
  harness.setLocale('ko')
  assert.equal(harness.core.getState().lang, 'ko')
  harness.core.actions.setSetting('completeCooldownMs', 0)
  harness.handlers['api-session/status']('s2', false)
  assert.equal(harness.notifications.at(-1).title, '턴 완료')
  harness.dispose()
})

// --- native settings surface ----------------------------------------------

test('the settings section renders native DSH primitives, not a custom stylesheet', () => {
  const harness = makeApplyHarness({ permission: 'granted', platform: 'windows' })
  const Section = harness.components['settings.section:notifications']
  const flat = flatten(Section({}))

  const switches = flat.filter((node) => node.__primitive === 'Switch')
  assert.ok(switches.length >= 7, 'the seven preference toggles must use the native Switch primitive')
  assert.ok(flat.some((node) => node.__primitive === 'Tag'), 'status uses the native Tag primitive')
  assert.ok(flat.some((node) => node.__primitive === 'Button'), 'actions use the native Button primitive')
  assert.ok(
    flat.every((node) => !('className' in (node.props ?? {}))),
    'no custom class hooks: every surface is a native primitive or token-styled layout node',
  )

  const styled = flat.filter((node) => node.props?.style && typeof node.props.style === 'object')
  for (const node of styled) {
    for (const [key, value] of Object.entries(node.props.style)) {
      if (key === 'fontFamily') assert.fail('a plugin must never set font-family')
      if (key === 'fontSize') {
        assert.match(String(value), /^var\(--dsh-content-font-size(?:-secondary)?,/, 'font size must be a DSH token')
      }
      if (key === 'lineHeight') {
        assert.match(String(value), /^calc\(\d+px \+ var\(--dsh-content-font-delta/, 'line height must include the DSH delta token')
      }
    }
  }
  harness.dispose()
})

test('the settings section hides the enable control when Chrome cannot grant permission', () => {
  const denied = makeApplyHarness({ permission: 'denied' })
  const deniedFlat = flatten(denied.components['settings.section:notifications']({}))
  const deniedEnable = deniedFlat.filter(
    (node) => node.__primitive === 'Button' && /Enable Chrome notifications/.test(String(node.children?.[0])),
  )
  assert.equal(deniedEnable.length, 0, 'a blocked permission shows guidance, not a broken enable button')
  denied.dispose()

  const fallback = makeApplyHarness({ permission: 'default' })
  const defaultFlat = flatten(fallback.components['settings.section:notifications']({}))
  assert.ok(
    defaultFlat.some((node) => node.__primitive === 'Button' && /Enable Chrome notifications/.test(String(node.children?.[0]))),
    'a pending permission exposes the enable button',
  )
  fallback.dispose()
})

test('the section icon is a DSH-native icon component', () => {
  const harness = makeApplyHarness()
  const Icon = harness.components['settings.section.icon:notifications']
  const tree = Icon({ size: 16, active: true })
  assert.equal(tree.type?.__primitiveName, 'IconAlarmClockOutlineRegular', 'use the host icon set, not a plugin icon')
  assert.equal(tree.props.size, 16)
  harness.dispose()
})

// --- removals --------------------------------------------------------------

test('no legacy notification path remains in the shipped client', () => {
  const source = readFileSync(new URL('../lib/client.js', import.meta.url), 'utf8')
  for (const removed of ['AudioContext', 'webkitAudioContext', 'indexedDB', 'data:audio', 'playChime', 'oscillator', 'soundEnabled', 'soundSource']) {
    assert.equal(source.includes(removed), false, 'legacy sound/BYO path must be gone: ' + removed)
  }
  for (const forbidden of ['XMLHttpRequest', 'WebSocket', 'EventSource', 'child_process', 'sendBeacon']) {
    assert.equal(source.includes(forbidden), false, 'no network/IPC/system path: ' + forbidden)
  }
})
