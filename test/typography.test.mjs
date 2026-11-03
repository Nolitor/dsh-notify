/**
 * Typography contract for the notifications settings section.
 *
 * The native Settings dialog renders at 14px with 12px descriptions (measured
 * distribution: 14px x20, 12px x11). DSH sets no font-size on <body>, so an
 * unset section root inherits 16px and the section reads visibly larger than
 * the settings around it. Measured 2026-11-03 before the fix: root 16px,
 * buttons 12px.
 */
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const source = readFileSync(new URL('../lib/client.js', import.meta.url), 'utf8')

test('the section root pins the native settings baseline', () => {
  const at = source.indexOf('.dshNbxSection{')
  assert.ok(at > 0, 'section rule must exist')
  const rule = source.slice(at, source.indexOf('}', at))
  assert.match(rule, /font-size:14px/, 'section must state 14px like native settings')
  assert.match(rule, /line-height:22px/, 'section must state the native 22px line height')
})

test('row titles match the native 14px and descriptions the native 12px', () => {
  const rule = (name) => {
    const at = source.indexOf('.' + name + '{')
    return at > 0 ? source.slice(at, source.indexOf('}', at)) : ''
  }
  assert.match(rule('dshNbxTitle'), /font-size:14px/)
  assert.match(rule('dshNbxCardTitle'), /font-size:14px/)
  assert.match(rule('dshNbxDesc'), /font-size:12px/)
})

test('no rule falls back to the 16px default', () => {
  assert.ok(!/font-size:16px/.test(source), '16px would inherit mismatch back in')
})

test('headings use the native emphasis weight 500, not 600', () => {
  // Measured live in the Settings dialog content area:
  //   native general section -> 14px/400 x15, 12px/400 x10, zero 14px/600
  //   the notify section    -> 14px/600 x6 before this fix
  // DSH's emphasis vocabulary for headings and titles is 500 (page H1 20px/500,
  // card H3 14px/500). A 600 heading reads heavier than every setting around it.
  for (const name of ['dshNbxHeading', 'dshNbxCardTitle']) {
    const at = source.indexOf('.' + name + '{')
    assert.ok(at > 0, name + ' rule must exist')
    const rule = source.slice(at, source.indexOf('}', at))
    assert.match(rule, /font-weight:500/, name + ' must use the native 500 weight')
    assert.ok(!/font-weight:600/.test(rule), name + ' must not use 600')
  }
})
