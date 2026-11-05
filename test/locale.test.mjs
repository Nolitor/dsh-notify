/**
 * Locale contract for Notify for Chrome.
 *
 * English is the default; Korean renders only while the host locale is Korean.
 * locale/*.json is the single source of truth: scripts/gen-locale.mjs bakes it
 * into lib/locale-table.js and scripts/build-client.mjs inlines that table into
 * lib/client.js. This test fails if the baked client is stale.
 */
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import vm from 'node:vm'
import { I18N } from '../lib/locale-table.js'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const readJson = (name) => JSON.parse(readFileSync(join(root, 'locale', name), 'utf8'))
const clientSource = readFileSync(join(root, 'lib', 'client.js'), 'utf8')

function loadClient() {
  let loaded = null
  const sandbox = {
    window: { __ModuleLoader__: { load(definition) { loaded = definition } } },
    document: { hasEventListener: () => false },
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
  vm.createContext(sandbox)
  vm.runInContext(clientSource, sandbox)
  const React = {
    createElement(type, props, ...children) {
      return { type, props: props ?? {}, children }
    },
    useState(initial) {
      return [typeof initial === 'function' ? initial() : initial, () => {}]
    },
    useEffect() {},
  }
  const primitives = new Proxy({}, { get: (_target, name) => (props) => ({ primitive: name, props }) })
  return loaded.factory((name) => {
    if (name === 'react') return React
    if (name === '@deepseek-ai/dsh-client-ui-primitives') return primitives
    throw new Error('unexpected require: ' + name)
  })
}

const en = readJson('en.json')
const ko = readJson('ko.json')

test('ko.json covers every key in en.json (and vice versa)', () => {
  assert.deepEqual(Object.keys(ko).sort(), Object.keys(en).sort())
})

test('every placeholder in an English string exists in Korean too', () => {
  const placeholders = (value) => String(value).match(/\{\w+\}/g)?.sort() ?? []
  for (const key of Object.keys(en)) {
    assert.deepEqual(placeholders(ko[key]), placeholders(en[key]), 'placeholder mismatch in ' + key)
  }
})

test('the baked table matches locale/*.json exactly', () => {
  assert.deepEqual(I18N, { en, ko }, 'lib/locale-table.js is stale; run npm run build')
  const generated = readFileSync(join(root, 'lib', 'locale-table.js'), 'utf8')
  const literal = /export const I18N = ([\s\S]*)$/.exec(generated)[1].trim().replace(/;\s*$/, '')
  assert.ok(
    clientSource.includes('const I18N = ' + literal),
    'lib/client.js is stale against lib/locale-table.js; run npm run build',
  )
})

test('market and locale display titles are the owner-named identity', () => {
  assert.equal(en.meta.title, 'Notify for Chrome')
  assert.equal(ko.meta.title, '알림 for 크롬')
  const market = JSON.parse(readFileSync(join(root, 'market', 'index.json'), 'utf8'))
  assert.equal(market.plugins[0].title.en, 'Notify for Chrome')
  assert.equal(market.plugins[0].title.ko, '알림 for 크롬')
})

test('Korean strings are actually Korean where they must be', () => {
  const korean = /[\uac00-\ud7a3]/
  for (const key of ['sectionTitle', 'title.complete', 'title.approval', 'action.enable', 'kinds.title']) {
    assert.match(ko[key], korean, key + ' is not Korean')
  }
  assert.equal(ko['title.complete'], '턴 완료')
  assert.equal(ko['title.approval'], '승인 필요')
})

test('no hardcoded Korean remains outside the baked dictionary', () => {
  const generated = readFileSync(join(root, 'lib', 'locale-table.js'), 'utf8')
  const literal = /export const I18N = ([\s\S]*)$/.exec(generated)[1].trim().replace(/;\s*$/, '')
  const stripped = clientSource.replace('const I18N = ' + literal, '')
  assert.equal(/[\uac00-\ud7a3]/.test(stripped), false, 'Korean text must live only in the locale dictionary')
})

test('translate() defaults to English and switches only on a Korean locale', () => {
  const module = loadClient()
  const { translate, normalizeLang } = module.__test
  assert.equal(translate('en', 'title.complete'), 'Turn complete')
  assert.equal(translate('ko', 'title.complete'), '턴 완료')
  assert.equal(translate('fr', 'title.complete'), 'Turn complete', 'unknown locales fall back to English')
  assert.equal(normalizeLang('ko-KR'), 'ko')
  assert.equal(normalizeLang('en-US'), 'en')
  assert.equal(normalizeLang(''), 'en')
  assert.equal(normalizeLang(undefined), 'en')
})
