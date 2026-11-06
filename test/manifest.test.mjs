/**
 * Manifest, version and rc.1 compliance contract for Notify for Chrome.
 *
 * Owner decisions recorded here:
 *   - the npm package name stays @nolit/dsh-notify-web (renaming it would break
 *     the live profile's `link:` dependency); only the display identity changed;
 *   - the owner's version form 0.0.1.rc3 maps to the semver form 0.0.1-rc.3;
 *   - DSH 0.2.2-rc.1 installs Cordis 4.1.0 and requires Node >= 24.9.
 */
import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (path) => readFileSync(join(root, path), 'utf8')
const pkg = JSON.parse(read('package.json'))
const market = JSON.parse(read('market/index.json'))
const patch = read('cordis.patch.yml')
const clientSource = read('lib/client.js')
const clientSrc = read('lib/client.src.js')

test('package name stays @nolit/dsh-notify-web; display identity is Notify for Chrome', () => {
  assert.equal(pkg.name, '@nolit/dsh-notify-web')
  assert.match(pkg.description, /Notify for Chrome/)
})

test('version is the owner-declared 0.0.1-rc.3 (owner form 0.0.1.rc3)', () => {
  assert.equal(pkg.version, '0.0.1-rc.3')
  assert.match(pkg.version, /^\d+\.\d+\.\d+-rc\.\d+$/)
  assert.equal(market.plugins[0].versions[0].version, pkg.version)
  assert.ok(read('CHANGELOG.md').includes('0.0.1.rc3'), 'CHANGELOG must record the owner-stated form')
})

test('cordis peer range admits the installed Cordis 4.1.0', () => {
  // Measured: @deepseek-ai/cordis 4.1.0 installed; the old ~4.0.6-alpha.1
  // range excluded it (docs/DSH-RC1-PLUGIN-DELTA.md item 1).
  assert.equal(pkg.peerDependencies['@deepseek-ai/cordis'], '^4.1.0')
})

test('Node engine floor is the rc.1 minimum 24.9', () => {
  assert.equal(pkg.engines.node, '>=24.9')
})

test('engines.dsh still admits the installed 0.2.2-rc.1 release', () => {
  assert.match(pkg.engines.dsh, />=0\.2\.2-alpha\.2/)
  assert.match(pkg.engines.dsh, /<0\.3\.0/)
})

test('rc.1 subpath exports are complete for display text and icons', () => {
  assert.equal(pkg.exports['./client'], './lib/client.js')
  assert.equal(pkg.exports['./icon'], './icon.svg')
  assert.equal(pkg.exports['./locale/*.json'], './locale/*.json')
  assert.equal(pkg.exports['./cordis.patch.yml'], './cordis.patch.yml')
})

test('every declared package file exists on disk', () => {
  for (const entry of pkg.files) {
    if (entry.includes('*')) continue
    assert.ok(existsSync(join(root, entry)), 'declared file missing: ' + entry)
  }
})

test('market lists the renamed plugin with the new version and no audio keywords', () => {
  const plugin = market.plugins[0]
  assert.equal(plugin.name, '@nolit/dsh-notify-web')
  assert.equal(plugin.title.en, 'Notify for Chrome')
  assert.equal(plugin.title.ko, '알림 for 크롬')
  assert.match(plugin.description.en, /Chrome notification/)
  assert.match(plugin.description.ko, /크롬 알림/)
  assert.equal(plugin.metadata.keywords.includes('web-audio'), false)
  assert.ok(plugin.metadata.keywords.includes('chrome'))
})

const defaultKeys = [
  ...clientSrc
    .slice(clientSrc.indexOf('DEFAULT_SETTINGS = Object.freeze({'), clientSrc.indexOf('})', clientSrc.indexOf('DEFAULT_SETTINGS = Object.freeze({')))
    .matchAll(/^\s{6}([A-Za-z0-9]+):/gm),
].map((match) => match[1])

test('the bundle patch configures exactly the settings the client normalizes', () => {
  assert.ok(defaultKeys.length >= 7, 'expected the settings keys in DEFAULT_SETTINGS')
  for (const key of defaultKeys) {
    assert.match(patch, new RegExp('^\\s+' + key + ':', 'm'), 'cordis.patch.yml is missing ' + key)
  }
  for (const removed of ['soundEnabled', 'soundSource', 'volume']) {
    assert.equal(patch.includes(removed), false, 'removed sound setting must be gone from the patch: ' + removed)
  }
})

test('the client half is the browser entry and the host half is a no-op', () => {
  assert.equal(pkg.main, 'lib/index.js')
  const host = read('lib/index.js')
  assert.equal(/node:fs|node:http|node:net|child_process|spawn/.test(host), false)
  assert.match(host, /export function apply/)
})

test('declared client inject graph covers the services the client uses', () => {
  const inject = pkg.dsh.client.inject
  for (const dependency of [
    '@deepseek-ai/dsh-api-remotes',
    '@deepseek-ai/dsh-client-locale',
    '@deepseek-ai/dsh-client-ui-renderer',
  ]) {
    assert.ok(inject.includes(dependency), 'client inject must declare ' + dependency)
  }
  assert.equal(pkg.dsh.client.platform, 'web')
})

test('no legacy notification / audio implementation survives in the shipped client', () => {
  for (const removed of ['AudioContext', 'indexedDB', 'data:audio', 'playChime', 'soundEnabled']) {
    assert.equal(clientSource.includes(removed), false, 'legacy path survived: ' + removed)
  }
})
