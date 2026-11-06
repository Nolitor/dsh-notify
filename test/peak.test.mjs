/**
 * Notify for Chrome — DeepSeek peak / off-peak tests.
 *
 * The decision table is the measured spec table from
 * docs/deepseek-peak-spec.md §5, re-run against the browser implementation.
 * Every case is expressed in KST (UTC+9) exactly as the spec states it, and the
 * expectation is the one the owner confirmed on 2026-11-06:
 *
 *   makeup workdays bill as OFF-PEAK.
 *
 * The official pricing footnote says weekends are off-peak "in full", so a
 * Saturday/Sunday 调休 makeup day stays off-peak. The Windows prototype
 * defaulted the other way; that divergence is resolved here and asserted.
 */
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'

const source = readFileSync(new URL('../lib/client.js', import.meta.url), 'utf8')

function loadModule() {
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
    isSecureContext: true,
  }
  vm.createContext(sandbox)
  vm.runInContext(source, sandbox)
  const React = {
    createElement(type, props, ...children) {
      return { type, props: props ?? {}, children }
    },
    useState(initial) {
      return [typeof initial === 'function' ? initial() : initial, () => {}]
    },
    useEffect() {},
  }
  const primitives = {}
  for (const name of ['Button', 'Input', 'Switch', 'Tag', 'Toast', 'IconAlarmClockOutlineRegular']) {
    const Primitive = function Primitive(props) {
      return { __primitive: name, props: props ?? {} }
    }
    primitives[name] = Primitive
  }
  const module = loaded.factory((name) => {
    if (name === 'react') return React
    if (name === '@deepseek-ai/dsh-client-ui-primitives') return primitives
    throw new Error('unexpected require: ' + name)
  })
  return module
}

const mod = loadModule()
const { peakDecision, peakNextChange, peakTimerText, peakRemainingParts, peakHolidayIndex, beijingDateKey, sevenSegmentLit } = mod.__test

/** KST wall clock (UTC+9) -> epoch ms, exactly as the spec table states cases. */
function kst(iso) {
  return Date.parse(`${iso}+09:00`)
}

/**
 * 2026 Chinese public holidays, verified 2026-11-06 against
 * https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2026.json
 * (33 off days, 6 makeup workdays). Kept inline so the table test never touches
 * the network.
 */
const HOLIDAYS_2026 = {
  year: 2026,
  papers: ['https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm'],
  days: [
    ...['2026-01-01', '2026-01-02', '2026-01-03'].map((date) => ({ date, isOffDay: true })),
    ...['2026-02-15', '2026-02-16', '2026-02-17', '2026-02-18', '2026-02-19', '2026-02-20', '2026-02-21', '2026-02-22', '2026-02-23'].map((date) => ({ date, isOffDay: true })),
    ...['2026-04-04', '2026-04-05', '2026-04-06'].map((date) => ({ date, isOffDay: true })),
    ...['2026-05-01', '2026-05-02', '2026-05-03', '2026-05-04', '2026-05-05'].map((date) => ({ date, isOffDay: true })),
    ...['2026-06-19', '2026-06-20', '2026-06-21'].map((date) => ({ date, isOffDay: true })),
    ...['2026-09-25', '2026-09-26', '2026-09-27'].map((date) => ({ date, isOffDay: true })),
    ...['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04', '2026-10-05', '2026-10-06', '2026-10-07'].map((date) => ({ date, isOffDay: true })),
    ...['2026-01-04', '2026-02-14', '2026-02-28', '2026-05-09', '2026-09-20', '2026-10-10'].map((date) => ({ date, isOffDay: false })),
  ],
}

// The published spec's eight cases. Case 7 changed value on 2026-11-06: the
// owner ruled makeup workdays off-peak, so a Saturday 调休 is now `false`.
const SPEC_CASES = [
  [1, '2026-10-20T01:00:00', false, 'weekday-offpeak'],
  [2, '2026-10-20T11:00:00', true, 'weekday-peak'],
  [3, '2026-10-20T14:00:00', false, 'weekday-offpeak'],
  [4, '2026-10-20T16:00:00', true, 'weekday-peak'],
  [5, '2026-10-24T11:00:00', false, 'weekend'],
  [6, '2026-10-01T11:00:00', false, 'holiday'],
  [7, '2026-10-10T11:00:00', false, 'makeup-workday'],
  [8, '2027-01-05T11:00:00', true, 'weekday-peak'],
]

test('spec §5 decision table holds, with makeup workdays off-peak', () => {
  for (const [id, iso, expected, reason] of SPEC_CASES) {
    const data = iso.startsWith('2027') ? null : HOLIDAYS_2026
    const decision = peakDecision(kst(iso), data)
    assert.equal(decision.isPeak, expected, `case #${id} (${iso}) isPeak`)
    assert.equal(decision.reason, reason, `case #${id} (${iso}) reason`)
  }
})

test('makeup workdays are off-peak on every published 2026 date', () => {
  const makeups = HOLIDAYS_2026.days.filter((day) => !day.isOffDay).map((day) => day.date)
  assert.equal(makeups.length, 6)
  for (const date of makeups) {
    // 10:00 KST is inside a UTC peak window on a weekday; only the makeup rule
    // can hold it off-peak.
    const at = Date.parse(`${date}T10:00:00+09:00`)
    const decision = peakDecision(at, HOLIDAYS_2026)
    assert.equal(decision.isPeak, false, `${date} must bill off-peak`)
    assert.equal(decision.reason, 'makeup-workday')
    assert.equal(decision.confidence, 'exact')
  }
})

test('peak windows are the fixed UTC definition', () => {
  // 01:00-04:00 and 06:00-10:00 UTC, Monday-Friday.
  const monday = '2026-10-19' // a Monday
  const cases = [
    ['00:59', false],
    ['01:00', true],
    ['03:59', true],
    ['04:00', false],
    ['05:59', false],
    ['06:00', true],
    ['09:59', true],
    ['10:00', false],
    ['23:59', false],
  ]
  for (const [time, expected] of cases) {
    const at = Date.parse(`${monday}T${time}:00Z`)
    assert.equal(peakDecision(at, HOLIDAYS_2026).isPeak, expected, `UTC ${time} on Monday`)
  }
})

test('the Beijing calendar day decides holidays, not the UTC day', () => {
  // 2026-10-01 is a holiday in Beijing. Beijing midnight is 16:00 UTC on the
  // previous UTC day, so the boundary must follow UTC+8.
  assert.equal(beijingDateKey(Date.parse('2026-09-30T16:00:00Z')), '2026-10-01')
  // One minute before Beijing midnight the day is an ordinary Wednesday; one
  // minute after, the holiday rule takes over. The hour itself is off-peak in
  // both cases, so the assertion is on the reason, not on isPeak.
  assert.equal(peakDecision(Date.parse('2026-09-30T15:59:00Z'), HOLIDAYS_2026).reason, 'weekday-offpeak')
  assert.equal(peakDecision(Date.parse('2026-09-30T16:00:00Z'), HOLIDAYS_2026).reason, 'holiday')
  assert.equal(peakDecision(Date.parse('2026-09-30T16:00:00Z'), HOLIDAYS_2026).confidence, 'exact')
})

test('an unpublished year degrades to estimated, never to a wrong answer', () => {
  const unpublished = { year: 2027, papers: [], days: [] }
  assert.equal(peakHolidayIndex(unpublished), null, 'empty papers means no usable index')
  const decision = peakDecision(kst('2027-01-05T11:00:00'), unpublished)
  assert.equal(decision.confidence, 'estimated')
  // 2027-01-05 is a Tuesday, so the weekday window still applies.
  assert.equal(decision.isPeak, true)
  assert.equal(decision.reason, 'weekday-peak')
})

test('a malformed payload is rejected instead of trusted', () => {
  assert.equal(peakHolidayIndex(null), null)
  assert.equal(peakHolidayIndex({}), null)
  assert.equal(peakHolidayIndex({ year: 2026, papers: ['x'] }), null, 'days must be an array')
  assert.equal(peakHolidayIndex({ year: 2026, papers: [], days: [{ date: '2026-01-01', isOffDay: true }] }), null)
  assert.equal(peakDecision(kst('2026-10-20T11:00:00'), { year: 2026, papers: ['x'], days: 'nope' }).confidence, 'estimated')
})

test('next change lands on the real boundary', () => {
  // Friday 2026-10-23 09:30 KST = 00:30 UTC, before that day's first peak.
  const at = kst('2026-10-23T09:30:00')
  const next = peakNextChange(at, HOLIDAYS_2026)
  assert.equal(new Date(next).toISOString(), '2026-10-23T01:00:00.000Z')

  // From inside the second peak window, the change is its 10:00 UTC end.
  const inside = Date.parse('2026-10-23T07:00:00Z')
  assert.equal(new Date(peakNextChange(inside, HOLIDAYS_2026)).toISOString(), '2026-10-23T10:00:00.000Z')

  // A Friday evening rolls through the weekend straight to Monday's first peak.
  const fridayEvening = Date.parse('2026-10-23T12:00:00Z')
  assert.equal(new Date(peakNextChange(fridayEvening, HOLIDAYS_2026)).toISOString(), '2026-10-26T01:00:00.000Z')
})

test('the countdown renders HH:MM:SS and clamps at zero', () => {
  const at = Date.parse('2026-10-23T01:00:00Z')
  assert.equal(peakTimerText(at, Date.parse('2026-10-22T22:45:30Z')), '02:14:30')
  assert.equal(peakTimerText(at, at), '00:00:00')
  assert.equal(peakTimerText(at, at + 60000), '00:00:00', 'never negative')
  // A long weekend must not truncate the hour field.
  const far = at + 100 * 3600 * 1000
  assert.equal(peakTimerText(far, at), '100:00:00')
  assert.equal(JSON.stringify(peakRemainingParts(null, at)), '{"hours":0,"minutes":0,"seconds":0,"total":0}')
})

// The module is evaluated in its own vm realm, so its arrays carry that
// realm's Array prototype. Compare by value rather than by prototype identity.
function lit(char) {
  return [...sevenSegmentLit(char)].join(',')
}

test('7-segment glyphs match the standard digit encoding', () => {
  assert.equal(lit(0), 'a,b,c,d,e,f')
  assert.equal(lit(1), 'b,c')
  assert.equal(lit(8), 'a,b,c,d,e,f,g')
  assert.equal(lit(7), 'a,b,c')
  assert.equal(lit(':'), '')
  assert.equal(lit('x'), '', 'an unknown glyph lights nothing')
  for (const digit of '0123456789') {
    assert.ok(lit(digit).length > 0, `digit ${digit} must light a segment`)
  }
})

test('the chip renders 7-segment SVG with DSH token colours only', () => {
  const markup = JSON.stringify(mod.__test.sevenSegmentText('01:23:45', {
    height: 14,
    colour: 'var(--dsw-alias-state-success-primary)',
    ghost: 'var(--dsw-alias-border-l2)',
    opacity: 0.9,
  }))
  assert.match(markup, /"type":"svg"/)
  assert.match(markup, /"type":"line"/)
  assert.equal(/#[0-9a-fA-F]{3,8}/.test(markup), false, 'no hardcoded hex colour')
  // Six digits plus two colons.
  const svgCount = (markup.match(/"type":"svg"/g) || []).length
  assert.equal(svgCount, 8)
})

// ---------------------------------------------------------------------------
// Route gate
//
// Owner report 2026-11-06: the chip appeared while the session was using
// `opencode-http-agent` (an OpenCode gateway route), not an official DeepSeek
// route. The peak clock is a property of DeepSeek's own billing, so a
// third-party route must render nothing.
// ---------------------------------------------------------------------------

const { OFFICIAL_DEEPSEEK_PROVIDER_IDS, isOfficialDeepSeekProvider, readActiveProvider } = mod.__test

test('only the official DeepSeek provider ids count as official', () => {
  assert.equal(
    JSON.stringify([...OFFICIAL_DEEPSEEK_PROVIDER_IDS]),
    JSON.stringify(['deepseek-official', 'deepseek-account']),
  )
  for (const id of OFFICIAL_DEEPSEEK_PROVIDER_IDS) {
    assert.equal(isOfficialDeepSeekProvider(id), true, `${id} is official`)
  }
})

test('gateway, reseller and proxy routes are not official', () => {
  const offRoute = [
    'opencode-http-agent',   // the route measured in the owner's report
    'opencode',
    'deepinfra',
    'antigravity',
    'deepseek',              // a bare name is not one of the registered ids
    'deepseek-official-x',   // no prefix matching
    'xdeepseek-official',
    '',
    null,
    undefined,
  ]
  for (const id of offRoute) {
    assert.equal(isOfficialDeepSeekProvider(id), false, `${String(id)} must not render the chip`)
  }
})

test('the provider is read from the model selector trigger attributes', () => {
  const makeDoc = (attrs) => ({
    querySelector(selector) {
      assert.equal(selector, '[data-provider-id][data-model-id]')
      if (!attrs) return null
      return { getAttribute: (name) => attrs[name] ?? null }
    },
  })
  assert.equal(readActiveProvider(makeDoc({ 'data-provider-id': 'deepseek-official' })), 'deepseek-official')
  assert.equal(readActiveProvider(makeDoc({ 'data-provider-id': 'opencode-http-agent' })), 'opencode-http-agent')
  assert.equal(readActiveProvider(makeDoc(null)), '', 'no composer node yet')
  assert.equal(readActiveProvider(null), '', 'no document')
  assert.equal(readActiveProvider({}), '', 'a document without querySelector')
})

// ---------------------------------------------------------------------------
// "Show timer on other providers" toggle
//
// Owner decision 2026-11-06: keep the official ids gated by default, and let the
// owner opt in to showing the timer on every route. The default must stay
// conservative: a third-party route has its own price sheet, and a wrong "50%
// off" claim is worse than a hidden widget.
// ---------------------------------------------------------------------------

const { peakAppliesToRoute } = mod.__test

test('the default hides the timer on non-official routes', () => {
  const settings = { peakOnAnyProvider: false }
  for (const id of ['opencode-http-agent', 'opencode', 'deepinfra', 'antigravity', '']) {
    assert.equal(peakAppliesToRoute(id, settings), false, `${id} stays hidden by default`)
  }
  for (const id of OFFICIAL_DEEPSEEK_PROVIDER_IDS) {
    assert.equal(peakAppliesToRoute(id, settings), true, `${id} renders by default`)
  }
})

test('missing or malformed settings still default to hidden', () => {
  assert.equal(peakAppliesToRoute('opencode-http-agent', undefined), false)
  assert.equal(peakAppliesToRoute('opencode-http-agent', {}), false)
  assert.equal(peakAppliesToRoute('opencode-http-agent', { peakOnAnyProvider: 'yes' }), false, 'truthy string is not opt-in')
  assert.equal(peakAppliesToRoute('opencode-http-agent', { peakOnAnyProvider: 1 }), false)
  assert.equal(peakAppliesToRoute('opencode-http-agent', { peakOnAnyProvider: false }), false)
})

test('opting in shows the timer on every route, official included', () => {
  const settings = { peakOnAnyProvider: true }
  for (const id of ['opencode-http-agent', 'opencode', 'deepinfra', 'antigravity', '', ...OFFICIAL_DEEPSEEK_PROVIDER_IDS]) {
    assert.equal(peakAppliesToRoute(id, settings), true, `${id} renders when opted in`)
  }
})

test('the setting defaults off in the shipped defaults and the bundle patch', () => {
  assert.equal(mod.__test.defaults.peakOnAnyProvider, false, 'DEFAULT_SETTINGS must ship it off')
  const patch = readFileSync(new URL('../cordis.patch.yml', import.meta.url), 'utf8')
  assert.match(patch, /^\s+peakOnAnyProvider: false$/m)
})
