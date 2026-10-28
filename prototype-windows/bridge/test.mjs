import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { apply, buildPopupArgs, createHandlers, createNotifier, isNotifyEnabled } from './index.js'

// 1) 팝업 인자에 스크립트 경로가 들어간다
const args = buildPopupArgs('C:\\root', 'DSH 작업 완료', '본문')
assert.equal(args[0], '-NoProfile')
assert.ok(args.includes('C:\\root\\notify\\popup.ps1'))

// 2) 코어가 있으면 스폰하지 않고 요청 파일만 남긴다
const root = mkdtempSync(join(tmpdir(), 'dsh-bridge-'))
mkdirSync(join(root, 'cache'))
let spawned = 0
const countingSpawn = () => {
  spawned += 1
  return { on() { } }
}
assert.equal(createNotifier(root, countingSpawn)('요청 제목', '요청 본문'), true)
assert.equal(spawned, 0)
const request = JSON.parse(readFileSync(join(root, 'cache', 'popup-request.json'), 'utf8'))
assert.equal(request.title, '요청 제목')
assert.equal(request.body, '요청 본문')

// 2b) 캐시 폴더가 없으면 스폰 폴백
assert.equal(createNotifier('C:\\root', countingSpawn, () => true)('t', 'b'), true)
assert.equal(spawned, 1)
assert.equal(createNotifier('C:\\root', countingSpawn, () => false)('t', 'b'), false)

// 3) 완료 이벤트: running=false 에서 1회, 5초 쿨다운
const calls = []
let clock = 1000
const notify = (title) => calls.push(title)
const handlers = createHandlers({ onComplete: true, onApproval: true, onQuestion: true, onError: true }, notify, () => clock)

handlers['api-session/status']('session-a', false)
assert.deepEqual(calls, ['DSH 작업 완료'])
handlers['api-session/status']('session-a', false)
assert.deepEqual(calls, ['DSH 작업 완료']) // 쿨다운

clock += 6000
handlers['api-session/status']('session-a', false)
assert.equal(calls.length, 2)
handlers['api-session/status']('session-a', true) // running=true 는 무시
assert.equal(calls.length, 2)

// 4) 승인/질문은 next 를 호출하고 알림도 남긴다
let nextCalls = 0
await handlers['approval/request']({}, async () => { nextCalls += 1 })
assert.equal(nextCalls, 1)
assert.ok(calls.includes('DSH 승인 필요'))
await handlers['user-questions/request']({}, async () => { nextCalls += 1 })
assert.equal(nextCalls, 2)
assert.ok(calls.includes('DSH 질문 대기'))

// 5) 오류 알림
handlers['agent/error']({ error: { message: 'boom' } })
assert.equal(calls.at(-1), 'DSH 오류')

// 6) apply 는 ctx.on 으로 핸들러를 등록한다
const registered = []
const ctx = { on(event) { registered.push(event) } }
apply(ctx, { notifyRoot: 'C:\\root', debugLog: '' })
assert.deepEqual(
  registered.sort(),
  ['agent/error', 'agent/status', 'agent/turn-stopping', 'api-session/status', 'approval/request', 'user-questions/request'].sort(),
)

// 6b) agent/status idle 도 완료 신호 — 같은 세션 중복은 쿨다운으로 1회
const agentCalls = []
let agentClock = 1000
const agentNotify = (title) => agentCalls.push(title)
const agentHandlers = createHandlers({}, agentNotify, () => agentClock)
agentHandlers['agent/status']({ status: 'running', agent: { id: 's1' } })
agentHandlers['api-session/status']('s1', false)
agentHandlers['agent/status']({ status: 'idle', agent: { id: 's1' } })
assert.equal(agentCalls.length, 1)
agentClock += 6000
agentHandlers['agent/status']({ status: 'idle', agent: { id: 's2' } })
assert.equal(agentCalls.length, 2)

// 6c) turn-stopping 도 완료 신호 — rest 직후 한 번, 쿨다운으로 중복 없음
const turnCalls = []
let turnClock = 1000
const turnHandlers = createHandlers({}, (title) => turnCalls.push(title), () => turnClock)
turnHandlers['agent/turn-stopping']({ agent: { id: 's3' }, turn: 1 })
turnHandlers['agent/status']({ status: 'idle', agent: { id: 's3' } })
assert.equal(turnCalls.length, 1)

// 7) 게이트: 알림 꺼짐 → 완료/질문 침묵, 승인은 next() 만 통과
const gateCalls = []
const gateNotify = (title) => gateCalls.push(title)
const offHandlers = createHandlers({}, gateNotify, () => 1000, { isEnabled: () => false, allowSession: () => true })
offHandlers['api-session/status']('session-a', false)
let nextCalls2 = 0
await offHandlers['approval/request']({}, async () => { nextCalls2 += 1 })
assert.deepEqual(gateCalls, [])
assert.equal(nextCalls2, 1)

// 8) 서브에이전트 완료는 팝업하지 않지만 승인 알림은 유지
const subCalls = []
const subNotify = (title) => subCalls.push(title)
const subHandlers = createHandlers({}, subNotify, () => 1000, { isEnabled: () => true, allowSession: () => false })
subHandlers['api-session/status']('child-session', false)
assert.deepEqual(subCalls, [])
await subHandlers['approval/request']({}, async () => {})
assert.deepEqual(subCalls, ['DSH 승인 필요'])

// 9) config.json 알림 스위치 읽기 (없거나 손상되면 켜짐)
assert.equal(isNotifyEnabled('C:\\root', () => JSON.stringify({ notifications: false })), false)
assert.equal(isNotifyEnabled('C:\\root', () => JSON.stringify({ notifications: true })), true)
assert.equal(isNotifyEnabled('C:\\root', () => JSON.stringify({})), true)
assert.equal(isNotifyEnabled('C:\\root', () => { throw new Error('missing') }), true)

console.log('bridge tests passed')
