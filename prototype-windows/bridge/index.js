/**
 * DSH Notify bridge — DeepSeek Harness 이벤트를 윈도 토스트로 바꾼다.
 *
 * 포트·웹서버 없음. 이벤트가 오면 `pwsh -File notify\send-toast.ps1` 을
 * 짧게 띄워 토스트를 보여주고 즉시 반환한다(fire-and-forget).
 *
 * 이벤트 선택:
 *   - api-session/status  : running=false → 턴 완료 1회 (세션·5초 쿨다운)
 *   - approval/request    : 도구 승인 대기 (waterfall — next() 를 그대로 넘김)
 *   - user-questions/request : 질문 대기 (waterfall)
 *   - agent/error         : 오류
 *   - session/created     : 세션 시작 시 피크 구간 경고(옵션)
 */

import { spawn } from 'node:child_process'
import { appendFileSync, existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

export const name = 'dsh-notify-bridge'
export const version = '0.5.0'

const DEFAULT_ROOT = 'C:\\Users\\nolit\\Workspace\\projects\\DSH Notify'

/** 우하단 팝업 CLI 인자. 테스트가 경로를 검증한다. */
export function buildPopupArgs(root, title, body) {
  return [
    '-NoProfile',
    '-NoLogo',
    '-File',
    join(root, 'notify', 'popup.ps1'),
    '-Title',
    title,
    '-Body',
    body,
  ]
}

const liveChildren = new Set()

/**
 * 알림 전달. 상주 코어가 살아 있으면 cache\popup-request.json 만 남긴다 —
 * 코어가 자기 프로세스에서 팝업과 소리를 처리하므로, 스폰된 자식에서 소리가 잘리던 문제를 피한다.
 * 캐시 폴더가 없으면 예전처럼 popup.ps1 을 스폰한다.
 */
export function createNotifier(root, spawnFn = spawn, exists = existsSync, onError = () => {}, onLifecycle = () => {}) {
  const popup = join(root, 'notify', 'popup.ps1')
  const toast = join(root, 'notify', 'send-toast.ps1')
  const cacheDir = join(root, 'cache')
  const requestPath = join(cacheDir, 'popup-request.json')

  return (title, body) => {
    try {
      if (exists(cacheDir)) {
        const temp = requestPath + '.tmp'
        writeFileSync(temp, JSON.stringify({ title, body, at: Date.now() }), 'utf8')
        renameSync(temp, requestPath)
        try { onLifecycle('popup request queued') } catch { }
        return true
      }
    } catch { }

    const script = exists(popup) ? popup : (exists(toast) ? toast : '')
    if (!script) return false
    try {
      const started = Date.now()
      const child = spawnFn('pwsh.exe', ['-NoProfile', '-NoLogo', '-Sta', '-File', script, '-Title', title, '-Body', body], {
        stdio: 'ignore',
        windowsHide: true,
      })
      liveChildren.add(child)
      try { onLifecycle(`popup spawn pid=${child.pid ?? '?'}`) } catch { }
      child.on?.('error', (error) => {
        liveChildren.delete(child)
        try { onError(error) } catch { }
      })
      child.on?.('exit', (code) => {
        liveChildren.delete(child)
        try { onLifecycle(`popup exit code=${code} after ${Date.now() - started}ms`) } catch { }
      })
      return true
    } catch {
      return false
    }
  }
}

/**
 * config.json 의 `notifications` 가 꺼져 있으면 알림을 보내지 않는다.
 * 파일이 없거나 손상되면 켜진 것으로 본다(알림을 조용히 잃지 않게).
 */
export function isNotifyEnabled(root, readFile = readFileSync) {
  try {
    const raw = readFile(join(root, 'config.json'), 'utf8')
    const config = JSON.parse(raw)
    return config?.notifications !== false
  } catch {
    return true
  }
}

/**
 * 이벤트 → 핸들러. 네트워크/시계/게이트를 주입해 결정적으로 테스트한다.
 * gates.isEnabled: 전체 알림 스위치, gates.allowSession: 서브에이전트 완료 제외.
 */
export function createHandlers(config, notify, now = () => Date.now(), gates = {}) {
  const handlers = {}
  const completeCooldownMs = Number(config?.completeCooldownMs ?? 5000)
  const lastComplete = new Map()
  const enabled = () => (typeof gates.isEnabled === 'function' ? gates.isEnabled() : true)
  const log = (message) => {
    try { gates.log?.(message) } catch { }
  }

  function complete(sessionId, source) {
    if (!enabled()) {
      log(`complete skipped (disabled) source=${source} session=${sessionId}`)
      return
    }
    if (typeof gates.allowSession === 'function' && !gates.allowSession(sessionId)) {
      log(`complete skipped (not root) source=${source} session=${sessionId}`)
      return
    }
    const timestamp = now()
    const previous = lastComplete.get(sessionId)
    if (previous !== undefined && timestamp - previous < completeCooldownMs) {
      log(`complete skipped (cooldown) source=${source} session=${sessionId}`)
      return
    }
    lastComplete.set(sessionId, timestamp)
    const sent = notify('DSH 작업 완료', '세션 작업이 끝났습니다. 결과를 확인하세요.')
    log(`complete notified source=${source} session=${sessionId} sent=${sent}`)
  }

  if (config?.onComplete !== false) {
    handlers['api-session/status'] = (sessionId, running) => {
      log(`event api-session/status session=${sessionId} running=${running}`)
      if (running) return
      complete(sessionId, 'api-session/status')
    }

    // 데스크톱 GUI 는 agent 상태로 턴 종료를 알린다 — api-session 이벤트가 없을 때의 보조 경로.
    handlers['agent/status'] = (payload) => {
      const status = payload?.status
      const sessionId = payload?.agent?.id
      log(`event agent/status session=${sessionId} status=${status}`)
      if (status !== 'idle' || !sessionId) return
      complete(sessionId, 'agent/status')
    }

    // serial 이벤트지만 동기적으로 즉시 알림만 쏘고 반환한다(턴 종료를 지연시키지 않음).
    handlers['agent/turn-stopping'] = (payload) => {
      const sessionId = payload?.agent?.id
      log(`event agent/turn-stopping session=${sessionId}`)
      if (!sessionId) return
      complete(sessionId, 'agent/turn-stopping')
    }
  }

  if (config?.onApproval !== false) {
    handlers['approval/request'] = async (_request, next) => {
      const sent = enabled() ? notify('DSH 승인 필요', '도구 실행 승인을 기다리고 있습니다.') : false
      log(`approval sent=${sent}`)
      return next()
    }
  }

  if (config?.onQuestion !== false) {
    handlers['user-questions/request'] = async (_request, next) => {
      const sent = enabled() ? notify('DSH 질문 대기', '모델이 답변을 기다리고 있습니다.') : false
      log(`question sent=${sent}`)
      return next()
    }
  }

  if (config?.onError !== false) {
    handlers['agent/error'] = (payload) => {
      const message = payload?.error?.message ?? '모델 요청 또는 도구 실행에서 오류가 발생했습니다.'
      const sent = enabled() ? notify('DSH 오류', String(message).slice(0, 160)) : false
      log(`error sent=${sent}`)
    }
  }

  return handlers
}

export function apply(ctx, config = {}) {
  const root = config.notifyRoot ?? DEFAULT_ROOT

  const debug = (line) => {
    if (!config.debugLog) return
    try {
      appendFileSync(config.debugLog, `[${new Date().toISOString()}] ${line}\n`)
    } catch { }
  }

  const notify = createNotifier(root, undefined, undefined, (error) => {
    debug(`spawn error: ${error?.message ?? error}`)
  }, (message) => debug(message))

  const allowSession = (sessionId) => {
    try {
      // apply 시점에는 agents 서비스가 아직 없을 수 있으므로 이벤트마다 조회한다.
      const service = ctx.get?.('agents')
      const agent = service?.get?.(sessionId)
      const roots = service?.roots?.() ?? []
      if (!agent || roots.length === 0) return true
      // 객체 동일성이 아닌 id 로 비교한다(레지스트리 조회와 roots() 가 다른 래퍼를 줄 수 있음).
      return roots.some((root) => root?.id === sessionId)
    } catch {
      return true
    }
  }

  const handlers = createHandlers(config, notify, undefined, {
    isEnabled: () => isNotifyEnabled(root),
    allowSession,
    log: debug,
  })

  for (const [event, handler] of Object.entries(handlers)) {
    // 에이전트 범위 이벤트(agent/status 등)는 기본 리스너에 전달되지 않는다.
    // { global: true } 로 범위 필터를 우회해 모든 에이전트 이벤트를 받는다.
    try {
      ctx.on(event, handler, { global: true })
    } catch {
      ctx.on(event, handler)
    }
  }

  if (config.debugLog) {
    try {
      appendFileSync(
        config.debugLog,
        `[${new Date().toISOString()}] bridge ${version} applied: ${Object.keys(handlers).join(', ')}\n`,
      )
    } catch {
      // 로그 실패는 무시 — 알림 경로에 영향 없음
    }
  }
}
