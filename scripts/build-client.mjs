#!/usr/bin/env node
/**
 * Bake lib/locale-table.js into lib/client.js.
 *
 * The browser loader evaluates lib/client.js as a plain script, so it cannot
 * import the locale module. This script replaces the ONE assignment placeholder
 * in lib/client.src.js with the literal table. The replacement is anchored to
 * the assignment line and the build FAILS if the placeholder survives, so a
 * stale or half-baked client.js can never ship (same failure the antigravity
 * track hit on 2026-11-05).
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const srcPath = join(root, 'lib', 'client.src.js')
const outPath = join(root, 'lib', 'client.js')

const src = readFileSync(srcPath, 'utf8')
const ASSIGNMENT = /const I18N = __NOTIFY_I18N__/
if (!ASSIGNMENT.test(src)) {
  console.error('build-client: lib/client.src.js has no "const I18N = __NOTIFY_I18N__" assignment')
  process.exit(1)
}

const generated = readFileSync(join(root, 'lib', 'locale-table.js'), 'utf8')
const match = /export const I18N = ([\s\S]*)$/.exec(generated)
if (!match) {
  console.error('build-client: lib/locale-table.js has no "export const I18N = ..."')
  process.exit(1)
}
const literal = match[1].trim().replace(/;\s*$/, '')

const out = src.replace(ASSIGNMENT, 'const I18N = ' + literal)
if (/__NOTIFY_I18N__/.test(out.replace(/\/\/[^\n]*/g, ''))) {
  console.error('build-client: placeholder survived the replacement')
  process.exit(1)
}
writeFileSync(outPath, out)
console.log('build-client: wrote lib/client.js')
