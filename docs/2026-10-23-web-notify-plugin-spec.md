# DSH 웹 알림 플러그인 — 단독 구현 사양

> 상태: proposed · 최종 갱신: 2026-10-23 · git: main @ 70a6606 · 상위: [README.md](../README.md)

- 전환 결정: 윈도우 상주 앱과 DSH 웹 플러그인은 **서로 완전히 독립된 2개 패키지**다.
- 이 문서는 **웹 플러그인 단독 사양**만 다룬다. 로컬 IPC/HTTP/파일 큐/포트/토큰/브리지 설계는 폐기한다.
- 윈도우 앱은 DSH 연동 없이 부팅 시 단독 실행되어 **오프피크 50% 타이머 위젯**만 표시한다.
- 웹 플러그인은 **Web Notification + Web Audio**만 사용한다. 별도 로컬 서버를 띄우지 않는다.
- 이번 단계에서 코드와 기존 파일은 수정하지 않았다.

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 아키텍처 결정 | 2개 독립 패키지, 통신 계층 없음 |
| 2 | 패키지 구조·설치 | `@nolit/dsh-notify-web`, web 프로필, no-op host |
| 3 | DSH 이벤트 계약 | 완료·승인·질문·오류 4종만 |
| 4 | 알림·오디오 | Notification, Web Audio, 권한 |
| 5 | 중복·다중 탭 | Web Locks 리더 + 쿨다운 |
| 6 | UI·설정 | 상태 배지, 인페이지 토스트, config |
| 7 | 라이프사이클·오류 | 로드/해제, 권한 거부, DSH 재시작 |
| 8 | 보안·프라이버시 | 네트워크/파일/민감정보 없음 |
| 9 | 테스트·수용 기준 | 단위/수동/회귀 매트릭스 |
| 10 | 로드맵·한계 | 2–3.5일, 3단계 |

---

## 1. 아키텍처 결정

```
[DSH 웹 플러그인]                         [DSH Notify 윈도우 앱]
 브라우저 API만 사용                        PowerShell/WPF 타이머 위젯
 Web Notification + Web Audio               카드·트레이·오프피크 타이머
 DSH 이벤트 구독(ctx.remote)                 DSH 이벤트 구독 없음
        │                                          │
        └────────── 서로 통신하지 않음 ────────────┘
```

| 결정 | 내용 |
|---|---|
| 패키지 분리 | 웹 플러그인과 윈도우 앱은 각자 독립 배포·버전·설정. 상호 import/의존 없음 |
| 통신 제거 | 로컬 HTTP 서버, 포트 탐색, `runtime.json`, 토큰, named pipe, 파일 큐, 프로세스 스폰 전부 없음 |
| 웹 플러그인 역할 | DSH 이벤트를 받아 **브라우저 알림과 브라우저 소리**만 낸다 |
| 윈도우 앱 역할 | DSH와 무관하게 **타이머/카드/트레이**만 표시한다 |
| 실패 격리 | 웹 플러그인이 없거나 실패해도 앱은 정상. 앱이 없어도 웹 플러그인은 정상 |

웹 플러그인의 host entry는 DSH Loader에 패키지를 등록하기 위한 **no-op**이다. 파일·포트·네트워크·프로세스 코드를 포함하지 않는다.

---

## 2. 패키지 구조·설치

```
plugin/
  package.json
  cordis.patch.yml
  lib/
    index.js        # no-op host entry (Loader 등록용)
    client.js       # 브라우저 알림 본체 (module-loader CJS factory)
  README.md
```

`package.json`:

```json
{
  "name": "@nolit/dsh-notify-web",
  "version": "0.1.0",
  "license": "MIT",
  "type": "module",
  "main": "lib/index.js",
  "exports": {
    ".": "./lib/index.js",
    "./client": "./lib/client.js",
    "./package.json": "./package.json"
  },
  "dsh": {
    "manifestVersion": 1,
    "bundle": { "patch": "./cordis.patch.yml" },
    "client": {
      "platform": "web",
      "immediately": true,
      "inject": [
        "@deepseek-ai/dsh-api-remotes",
        "@deepseek-ai/dsh-client-ui-session",
        "@deepseek-ai/dsh-client-ui-slots"
      ]
    }
  },
  "engines": { "node": ">=24", "dsh": ">=0.2.1-rc.2 <0.3.0" },
  "peerDependencies": { "@deepseek-ai/cordis": "~4.0.5" }
}
```

`cordis.patch.yml`:

```yaml
- insert:
    - id: dsh-notify-web
      name: '@nolit/dsh-notify-web'
      config:
        notifyOnComplete: true
        notifyOnApproval: true
        notifyOnQuestion: true
        notifyOnError: true
        completeCooldownMs: 5000
        soundEnabled: true
        volume: 0.3
        suppressWhenFocused: false
        requireInteractionForApproval: true
        notifyOnSubagents: false
```

`lib/index.js` — 통신 없는 no-op:

```js
export const name = 'dsh-notify-web'
export function apply() {}
```

`lib/client.js` — 뼈대:

```js
window.__ModuleLoader__.load({
  id: '@nolit/dsh-notify-web',
  factory: (require) => {
    const React = require('react')
    const exports = {}
    exports.inject = ['remote', 'sessions', 'slots', 'locale']
    exports.apply = (ctx) => {
      // ctx.remote.$on(...) 4종 구독
      // ctx.slots.register(...) 배지/토스트/패널
    }
    return exports
  },
})
```

**설치:** web 프로필의 `dsh.profile.bundles`에 `@nolit/dsh-notify-web`을 추가하고, 프로필 `node_modules/@nolit/dsh-notify-web`을 이 폴더에 링크한다. `dsh plugin --profile web add link:<절대경로>`로 의존성을 추가한 뒤 번들 목록에 등록한다. desktop 브리지(`@local/dsh-notify-bridge`)는 이 패키지와 무관하며, 검증 후 별도로 제거한다.

**에셋 정책:** 이 패키지는 폰트/로고/사운드 파일을 번들하지 않는다. 기본 아이콘은 중립 시계 SVG(MIT)이며, 알림에는 아이콘을 지정하지 않는다. 사용자 주입 에셋의 책임 범위는 [에셋·상표 라이선스 정책](2026-10-23-asset-policy.md)을 따른다.

**빌드:** v1은 손으로 작성한 `lib/client.js`를 쓴다. 별도 번들러가 없어 `lib/client.js`가 없으면 로드가 실패하므로 파일 존재를 테스트로 확인한다. 수정 후에는 페이지 새로고침(또는 DSH 재시작)을 기본으로 한다.

---

## 3. DSH 이벤트 계약

브라우저로 전달되는 이벤트만 사용한다. DSH 0.2.1-rc.2 설치본의 포워딩 허용 목록 기준.

| 이벤트 | 시그니처 | 사용 | 처리 |
|---|---|---|---|
| `api-session/status` | `(sessionId, running)` | 완료 | `running === false`이고 루트 세션이면 알림. 세션별 5초 쿨다운 |
| `api-session/error` | `(sessionId, message)` | 오류 | 루트 세션이면 알림. 메시지 160자 절단 |
| `approval/request` | `(request, next)` | 승인 | 즉시 알림 후 `next()` 통과. `next()`는 정확히 1회 |
| `user-questions/request` | `(request, next)` | 질문 | 즉시 알림 후 `next()` 통과. `next()`는 정확히 1회 |

**사용 금지:**

- `agent/turn-stopping` — serial(awaited) 이벤트라 턴 종료를 지연시킬 수 있다.
- `agent/error` — 브라우저 포워딩 허용 목록에 없다. `api-session/error`를 쓴다.
- `agent/status` — 브라우저 포워딩 허용 목록에 없다. 완료는 `api-session/status`로 판정한다.

**루트 세션 필터:**

```js
const row = ctx.sessions.list.getSnapshot().byId[sessionId]
const isRoot = !row || (!row.parentId && row.origin !== 'subagent')
```

행이 아직 목록에 없으면 알림을 잃지 않기 위해 루트로 간주한다. `notifyOnSubagents`가 true면 필터를 끈다(기본 false). 승인/질문은 서브에이전트 것도 사람이 답해야 하므로 기본적으로 알린다.

**승인/질문 지연 금지:**

```js
ctx.remote.$on('approval/request', function (request, next) {
  try { notifyApproval(this, request) } catch {}
  return next()
})
```

`notifyApproval`은 `async`로 만들지 않거나, 만들어도 `await`하지 않는다. 네트워크/권한 요청이 승인 UI를 막으면 안 된다.

**완료 판정:**

```js
const last = new Map() // sessionId -> timestamp
ctx.remote.$on('api-session/status', (sessionId, running) => {
  if (running) return
  if (!enabled('complete')) return
  if (!isRoot(sessionId)) return
  const now = Date.now()
  if (now - (last.get(sessionId) ?? 0) < config.completeCooldownMs) return
  last.set(sessionId, now)
  notify('complete', sessionId)
})
```

---

## 4. 알림·오디오

### 4.1 Web Notification

- `Notification.permission === 'granted'`일 때만 `new Notification(...)`을 호출한다.
- `default`일 때 자동 요청하지 않는다. 브라우저가 사용자 제스처를 요구하며, 무단 프롬프트는 UX를 해친다. 상태 패널의 **“브라우저 알림 켜기”** 클릭에서만 `requestPermission()`을 호출한다.
- `denied`이면 인페이지 토스트로 폴백하고 배지에 “알림 차단됨”을 표시한다.

```js
new Notification(title, {
  body,
  tag: `dsh-notify:${sessionId}:${kind}`, // 같은 세션/종류는 OS가 합침
  silent: true,                            // 소리는 Web Audio가 담당
  requireInteraction: kind === 'approval' || kind === 'question',
})
```

- `tag`로 같은 세션의 연속 완료 알림을 OS 수준에서 합친다.
- 클릭 시 `window.focus()` 후 `notification.close()`. 세션 딥링크는 v1에서 하지 않는다.
- 본문은 고정 문구 + 세션 제목 80자. 프롬프트/코드/도구 인자는 넣지 않는다.

| kind | title | body |
|---|---|---|
| complete | `DSH 작업 완료` | `세션 작업이 끝났습니다. 결과를 확인하세요.` |
| approval | `DSH 승인 필요` | `도구 실행 승인을 기다리고 있습니다.` |
| question | `DSH 질문 대기` | `모델이 답변을 기다리고 있습니다.` |
| error | `DSH 오류` | `모델 요청 또는 도구 실행에서 오류가 발생했습니다.` |

### 4.2 Web Audio

- 첫 사용자 제스처(패널의 “소리 켜기” 또는 “테스트 알림”)에서 `AudioContext`를 만들고 `resume()`한다.
- 알림음은 에셋 없이 합성한다. 예: 880Hz 120ms → 1175Hz 120ms, gain 0.3, exponential ramp.
- `soundEnabled`가 false면 재생하지 않는다.
- `AudioContext`가 `suspended`면 재생을 시도하되, 실패해도 알림 자체는 막지 않는다.
- 페이지가 백그라운드여도 오디오는 재생될 수 있다. 브라우저가 정책상 막으면 무음이 되며, 배지에 “소리 잠김”을 표시한다.
- 알림음은 실제 알림이 표시될 때 1회만 재생한다. 인페이지 토스트만 뜨는 경우에도 1회 재생한다.

### 4.3 포커스/가시성

- `suppressWhenFocused`가 true이고 `document.hasFocus()`가 true이면 완료 알림은 인페이지 토스트만 띄운다(승인/질문은 항상 Notification).
- 기본값 false: 다른 창을 보고 있어도 OS 알림을 띄운다.
- `pageVisible`/`pageFocused`는 로그/디버그에만 쓰고 알림 본문에는 넣지 않는다.

---

## 5. 중복·다중 탭

같은 DSH 페이지를 여러 탭에 열면 각 탭이 같은 이벤트를 받아 알림이 중복된다.

1. **Web Locks 리더**
   ```js
   navigator.locks.request('dsh-notify-leader', { mode: 'exclusive' }, async () => {
     leader = true
     await new Promise(() => {}) // 탭 종료까지 유지
   })
   ```
   리더만 Notification/오디오를 낸다. 탭이 닫히면 락이 풀리고 다른 탭이 승계한다.
2. **폴백 리더**: Web Locks가 없거나 보안 컨텍스트가 아니면 `localStorage` 리스(10초 TTL, 3초 갱신)로 선출한다. `storage` 이벤트로 리더 변경을 감지한다.
3. **이벤트 id**: `crypto.randomUUID()`(없으면 `sessionId-kind-timestamp-random`). 서버가 없으므로 앱 멱등성은 필요 없다.
4. **쿨다운**: 같은 세션 완료 5초. `running=true` 수신 시 쿨다운을 리셋한다.
5. **Notification tag**: 같은 세션/종류의 알림을 OS가 합치도록 한다.

리더가 아니어도 상태 배지는 각 탭에서 갱신한다. 리더 변경 시 배지 툴팁에 “이 탭이 알림 담당”을 표시한다.

---

## 6. UI·설정

### 6.1 상태 배지

`sidebar.footer.action` 슬롯에 작은 점/배지를 등록한다.

| 상태 | 표시 | 클릭 시 |
|---|---|---|
| 권한 granted + 오디오 언락 | 녹색 점 | 상태 패널 |
| 권한 default (미요청) | 주황 점 | 상태 패널 + “알림 켜기” 강조 |
| 권한 denied | 회색 점 + `!` | 상태 패널(차단 안내) |
| Notification 미지원 | 회색 점 | 인페이지 토스트만 사용 안내 |

### 6.2 상태 패널

`shell.overlay` 또는 배지 클릭 팝업으로 다음을 제공한다.

- 현재 권한/오디오 상태.
- **브라우저 알림 켜기** — `Notification.requestPermission()`.
- **소리 켜기** — `AudioContext` 생성/`resume()`.
- **테스트 알림** — `complete` 알림 1회.
- 종류별 토글(완료/승인/질문/오류)과 소리 on/off.
- “이 탭이 알림 담당” 표시(리더 여부).

설정은 `localStorage`에 저장한다(키: `dsh-notify-web:settings`). DSH 프로필 config는 초기 기본값으로만 사용하고, 사용자 토글은 브라우저에 저장한다. 서버/파일 저장은 하지 않는다.

### 6.3 인페이지 토스트

- `shell.overlay`에 6초 자동 닫힘 토스트를 등록한다.
- Notification이 거부/미지원일 때, 또는 `suppressWhenFocused`로 OS 알림을 생략했을 때 사용한다.
- 제목/본문/닫기 버튼만. 클릭하면 토스트를 닫고 `window.focus()`.
- 최대 3개까지 스택, 같은 `tag`는 교체.

### 6.4 설정 스키마

```json
{
  "notifyOnComplete": true,
  "notifyOnApproval": true,
  "notifyOnQuestion": true,
  "notifyOnError": true,
  "completeCooldownMs": 5000,
  "soundEnabled": true,
  "volume": 0.3,
  "suppressWhenFocused": false,
  "requireInteractionForApproval": true,
  "notifyOnSubagents": false
}
```

경로·포트·토큰·앱 관련 키는 **없다.**

---

## 7. 라이프사이클·오류

```
플러그인 로드
  ├─ 권한/설정 로드(localStorage + config 기본값)
  ├─ ctx.remote.$on 4종 등록
  ├─ 슬롯(배지/토스트/패널) 등록
  └─ Web Locks 리더 시도

플러그인 해제
  ├─ 이벤트 구독 해제
  ├─ 슬롯 해제
  ├─ 리더 락 해제(탭 종료 시 자동)
  └─ AudioContext close
```

| 상황 | 동작 |
|---|---|
| 권한 default | 자동 요청하지 않음. 배지 주황, 패널에서 요청 |
| 권한 denied | Notification 생략, 인페이지 토스트. 배지 회색 |
| 오디오 잠김 | 알림은 정상, 소리만 생략. 배지 툴팁 안내 |
| Notification 미지원 | 인페이지 토스트만 |
| DSH 재시작 | 페이지가 새로 로드되며 플러그인 재적용. 상태는 localStorage에서 복원 |
| DSH 포트 변경 | 새 출처가 되어 권한/오디오를 다시 받아야 함. 코드 수정은 없음 |
| 탭 닫힘 | 그 탭의 리더/알림 종료. 다른 탭이 있으면 승계, 없으면 알림 없음 |
| 이벤트 핸들러 예외 | `try/catch`로 삼키고 `ctx.logger.warn` 1회. DSH 턴에 영향 없음 |
| 승인/질문 | 알림 실패와 무관하게 `next()` 통과 |

**로깅:** `ctx.logger.debug/info/warn`만 사용한다. 파일 로그를 만들지 않는다. 민감정보(프롬프트/코드/토큰)는 로그에도 남기지 않는다.

---

## 8. 보안·프라이버시

- 네트워크 요청 없음: `fetch`, `XMLHttpRequest`, WebSocket, `EventSource`를 새로 만들지 않는다. DSH의 기존 Remote 채널만 쓴다.
- 파일 시스템 접근 없음: `%LOCALAPPDATA%`, `runtime.json`, 로그 파일을 읽지 않는다.
- 로컬 서버/포트 없음: 리스너를 열지 않는다.
- 알림 내용: 고정 문구 + 세션 제목 80자. 프롬프트 원문/도구 인자/코드/첨부 파일명은 넣지 않는다.
- OS 알림은 잠금 화면에 보일 수 있음을 문서화한다. 민감한 세션 제목은 사용자가 설정에서 끌 수 있다(`showSessionTitle` 옵션은 v1.1 후보).
- 권한은 사용자 제스처로만 요청한다. 자동 프롬프트/반복 프롬프트 금지.
- 외부 링크/URL을 열지 않는다. 클릭은 `window.focus()`만.

---

## 9. 테스트·수용 기준

### 단위 테스트(모의 객체)

| ID | 케이스 | 기대 |
|---|---|---|
| U1 | `api-session/status(false)` 루트 | 알림 1회 |
| U2 | 같은 세션 5초 내 재수신 | 추가 알림 없음 |
| U3 | `running=true` 후 다시 false | 쿨다운 리셋, 알림 1회 |
| U4 | 서브에이전트(`parentId`/`origin`) | 알림 없음 |
| U5 | `approval/request` | 알림 + `next()` 1회, 지연 없음 |
| U6 | `user-questions/request` | 알림 + `next()` 1회 |
| U7 | `api-session/error` | 오류 알림, 160자 절단 |
| U8 | 권한 denied | Notification 미호출, 토스트 호출 |
| U9 | 다중 탭(리더 2개 시뮬레이션) | 리더만 알림 |
| U10 | 오디오 잠김 | 알림은 정상, 예외 없음 |

### 수동 E2E

1. DSH web 실행, 플러그인 로드.
2. 패널에서 알림/소리 켜기 → 테스트 알림.
3. 턴 완료 → OS 알림 1회 + 소리 1회.
4. 승인 대기 → 알림 + 승인 UI 정상, 턴 지연 없음.
5. 탭 2개 → 알림 1회.
6. 권한 거부 → 인페이지 토스트.
7. DSH를 다른 포트로 재실행 → 코드 수정 없이 동작, 권한 재요청 UX.
8. 앱(윈도우 위젯) 종료/실행과 무관하게 웹 알림 동작.

### 회귀

- `pwsh -NoProfile -File tests\run-all.ps1` — 기존 19/19 유지(앱 변경 없음).
- `pwsh -NoProfile -File tests\docs-contract.ps1` — 새 문서 포함 통과.
- 웹 플러그인은 로컬 파일/포트를 만들지 않으므로 기존 앱 테스트에 영향 없음.

### 수용 기준

| ID | 기준 |
|---|---|
| A1 | DSH 탭이 열려 있으면 완료/승인/질문/오류 알림이 브라우저 API만으로 동작 |
| A2 | 로컬 앱이 없어도, 있어도 웹 플러그인 동작이 동일 |
| A3 | 어떤 로컬 포트/HTTP/파일 IPC도 사용하지 않음(코드 검색으로 확인) |
| A4 | 승인/질문 `next()` 지연 < 50ms |
| A5 | 다중 탭에서 알림 1회 |
| A6 | 권한 거부 시 인페이지 토스트 폴백 |
| A7 | DSH 포트 변경 시 코드/설정 수정 없이 동작(권한 재승인 제외) |
| A8 | 알림 본문에 프롬프트/코드/토큰 없음 |
| A9 | DSH 탭 닫힘 시 알림 없음(한계로 문서화) |

---

## 10. 로드맵·한계

| Phase | 내용 | 산출물 | 예상 |
|---|---|---|---|
| 1 | 패키지 골격·이벤트 구독 | `package.json`, `cordis.patch.yml`, no-op host, `client.js` 구독/필터/쿨다운 | 0.5–1일 |
| 2 | 알림·오디오·권한·UI | Notification/Web Audio, 배지/패널/토스트, 권한 UX | 1–1.5일 |
| 3 | 다중 탭·하드닝·문서 | Web Locks 리더, 테스트, README, 설치 절차 | 0.5–1일 |

**총 2–3.5일.** 앱 변경이 없으므로 기존 19개 테스트는 그대로 기준선이다.

| 한계/위험 | 영향 | 대응 |
|---|---|---|
| DSH 탭이 닫히면 알림 없음 | 백그라운드 알림 불가 | 설계상 수용. 필요하면 DSH 자체 백그라운드 알림을 별도 검토 |
| 알림 권한은 출처 단위 | 포트 변경 시 재승인 | 배지/패널에서 명확히 안내, 자동 재프롬프트 금지 |
| 오디오 자동재생 차단 | 첫 알림 무음 가능 | 첫 제스처 언락, “소리 켜기” 버튼, 무음 허용 |
| 백그라운드 탭 타이머 스로틀 | 쿨다운/배지 갱신 지연 가능 | 이벤트 기반 처리, `setInterval` 최소화 |
| DSH 클라이언트 API 변경 | 구독/슬롯 깨짐 | `engines.dsh` 고정, 이벤트 4종 단위 테스트 |
| 알림 피로 | 사용자가 끔 | 종류별 토글, 세션 쿨다운, 포커스 시 완료 억제 옵션 |
| OS 알림 잠금 화면 노출 | 프라이버시 | 본문 고정 문구, 세션 제목 표시 옵션(후속) |
| 다중 탭 리더 경합 | 일시적 중복/누락 | Web Locks 원자성, 폴백 리스, 테스트 |

---

## 부록: 금지 패턴 체크리스트

- [ ] `fetch(`, `XMLHttpRequest`, `WebSocket`, `EventSource`로 로컬 서버를 호출하지 않는다.
- [ ] `runtime.json`, `%LOCALAPPDATA%`, `node:fs`, `node:net`을 쓰지 않는다.
- [ ] 포트 번호(3080, 47600 등)를 상수로 두지 않는다.
- [ ] `agent/turn-stopping`, `agent/error`를 구독하지 않는다.
- [ ] 승인/질문 핸들러에서 `await`로 `next()`를 지연하지 않는다.
- [ ] 알림 본문에 프롬프트/코드/토큰을 넣지 않는다.
