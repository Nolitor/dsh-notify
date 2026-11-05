/**
 * Typography and style-isolation contract for Notify for Chrome.
 *
 * CORRECTION to the old v1.0 pixel rule (F-41): DSH defines a live, user-
 * configurable content font size. Measured in the shipped stylesheet and the
 * theme client (2026-11-05):
 *
 *   body{--dsh-content-font-delta:calc(var(--dsh-content-font-size,14px) - 14px);}
 *   --dsh-content-font-size-secondary:min(calc(var(--dsh-content-font-size,14px) - 1px), ...)
 *   FONT_SIZE_SPECS.text = { variable: '--dsh-content-font-size', min: 10, max: 22, default: 14 }
 *
 * So every size must be a token with the DSH fallback — never a literal px —
 * and the plugin must not ship a stylesheet, a font family or hardcoded colours.
 */
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const source = readFileSync(join(root, 'lib', 'client.js'), 'utf8')

test('the plugin ships no stylesheet and injects no CSS into the document', () => {
  for (const forbidden of ['document.head', 'appendChild', "createElement('style')", 'createElement("style")', 'data-plugin-css', 'textContent = \'']) {
    assert.equal(source.includes(forbidden), false, 'no self-authored stylesheet: ' + forbidden)
  }
  assert.equal(source.includes('!important'), false)
})

test('no font-family is ever set (the host and the Korean pack own family)', () => {
  assert.equal(/fontFamily/.test(source), false, 'use inherit only by not setting a family')
  assert.equal(/font-family/.test(source), false)
})

test('every font size is a live DSH content-size token', () => {
  const values = [...source.matchAll(/fontSize:\s*'([^']+)'/g)].map((match) => match[1])
  assert.ok(values.length >= 2, 'expected the content and secondary typography tokens')
  for (const value of values) {
    assert.match(
      value,
      /^var\(--dsh-content-font-size(?:-secondary)?, \d+px\)$/,
      'font size must be the DSH token form with its fallback, got: ' + value,
    )
  }
})

test('every line height includes the live DSH delta token', () => {
  const values = [...source.matchAll(/lineHeight:\s*'([^']+)'/g)].map((match) => match[1])
  assert.ok(values.length >= 2, 'expected the content and secondary line heights')
  for (const value of values) {
    assert.match(
      value,
      /^calc\(\d+px \+ var\(--dsh-content-font-delta(?:-secondary)?, 0px\)\)$/,
      'line height must follow the size delta, got: ' + value,
    )
  }
})

test('no literal pixel font size exists anywhere', () => {
  assert.equal(/font-size:\s*\d+px/.test(source), false)
  assert.deepEqual(
    [...source.matchAll(/fontSize:\s*\d+/g)].map((match) => match[0]),
    [],
    'a numeric fontSize cannot follow the user setting',
  )
})

test('all colours come from --dsw tokens', () => {
  const colours = [
    ...source.matchAll(/(?:^|[\s{,])(?:color|background):\s*'([^']+)'/g),
  ].map((match) => match[1])
  assert.ok(colours.length >= 4, 'expected the styles object colour declarations')
  for (const value of colours) {
    assert.ok(value.startsWith('var(--dsw-'), 'colour must be a DSH token, got: ' + value)
  }
  assert.equal(/#[0-9a-fA-F]{3,8}\b/.test(source), false, 'no hardcoded hex colours')
  assert.equal(/rgba?\(/.test(source), false, 'no hardcoded rgb() colours')
})

test('the section never sizes body/html/:root or a bare element via a sheet', () => {
  // There is no sheet at all now; this guards against reintroducing one.
  assert.equal(/body\s*\{/.test(source), false)
  assert.equal(/:root\s*\{/.test(source), false)
})
