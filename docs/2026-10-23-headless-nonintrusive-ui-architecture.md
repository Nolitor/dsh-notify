# DSH 알림 웹 플러그인 — 헤드리스 코어 + 비침습 UI 아키텍처

> 상태: proposed · 최종 갱신: 2026-10-23 · git: main @ 8129b54 · 상위: [README.md](../README.md)

- 목적: BYO 에셋·라이선스 정책과 UI 비침습 원칙을 하나의 **단독 웹 플러그인 완성 설계**로 통합한다.
- 범위: DSH 웹 플러그인만. 윈도우 위젯과의 통신은 없다.
- 이번 단계에서는 **코드 파일을 쓰지 않는다.** 이 보고서만 제출한다.
- 이전 초안의 `sidebar.footer.action` 고정 배치는 폐기하고, 아래 구조를 기준으로 재작성한다.

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 최종 결정 | 설정은 `settings.section`, 알림 UI는 `shell.overlay`, 코어는 슬롯 비의존 |
| 2 | UI 실측 | 뷰포트·사이드바 접힘·푸터 구조·z-index 레이어 |
| 3 | 간섭 분석 | 푸터/헤더/플로팅/모달의 레이아웃 리스크 |
| 4 | 진입점 비교 | 공식 설정 섹션이 최적, 푸터·배지는 보조 이하 |
| 5 | 헤드리스 코어 | 이벤트·필터·권한·오디오·저장·리더를 UI에서 분리 |
| 6 | UI 어댑터 | 설정 섹션·동의 카드·토스트만 얇게 연결 |
| 7 | BYO 에셋 정책 | MIT, 번들 없음, Web Audio 합성 + 사용자 오디오 |
| 8 | 사용자 흐름 | 첫 설치·설정·알림·다중 탭·접힘 상태 |
| 9 | 구현 계약 | 파일 구조, 코어 API, 상태 스키마 |
| 10 | 검증 계획 | 뷰포트/z-index/권한/오디오/다중 탭 매트릭스 |
| 11 | 리스크·결정 | 남은 위험과 확정 필요 항목 |

---

## 1. 최종 결정

| 영역 | 결정 |
|---|---|
| 코어 | React·슬롯·DOM 렌더링을 모르는 **헤드리스 엔진** 하나 |
| 설정 진입점 | DSH 공식 **`settings.section`** (Settings 모달 내 "알림" 섹션) |
| 첫 사용 동의 | **`shell.overlay`**의 일회성 비모달 카드 |
| 알림 폴백 | **`shell.overlay`**의 일시적 토스트 스택 |
| 사이드바 | **아무것도 추가하지 않는다.** 푸터 액션·토글 배지 없음 |
| 헤더 | 사용하지 않는다(세션 스코프·비전역) |
| 영구 배지 | 사용하지 않는다(콘텐츠 가림·z-index 충돌) |
| 오디오 | 기본은 Web Audio 합성, 사용자 BYO 오디오는 선택 |
| 라이선스 | MIT, 폰트/로고/오디오 번들 없음 |

**한 문장:** 알림의 두뇌는 슬롯 밖에 두고, 사용자가 설정할 때만 공식 Settings 모달 안에 나타나며, 평소에는 사이드바/헤더를 전혀 건드리지 않는다.

---

## 2. UI 실측

### 2.1 프레임과 뷰포트

| 항목 | 실측/계약 | 의미 |
|---|---|---|
| 앱 프레임 | 3열 그리드 `sidebar \| center \| rightbar`, `overflow:hidden`, `height:100%` | 전체 뷰포트를 프레임이 소유 |
| 사이드바 폭 | 264–420px, 기본 280px | 좁은 화면에서도 264px 이상 |
| 접힘 레일 | 56px | 아이콘만 남는 상태 |
| 자동 접힘 | 뷰포트 < 1024px | 좁은 창에서 사이드바가 자동으로 레일이 됨 |
| 우측 패널 | 기본 45%, 최대 70%, 중앙 최소 400px | 우측 패널이 열리면 사이드바가 접힐 수 있음 |
| 오버레이 레이어 | `position:absolute; inset:0; z-index:20; pointer-events:none` | 프레임 전체를 덮는 비모달 레이어 |
| 설정 모달 | `z-index:1000`, 800×800 max, nav 188px | 모달이 열리면 오버레이(z20)보다 위 |
| 메뉴/팝오버 | `z-index:100`, 일부 포털 `1100` | 일반 팝오버가 오버레이보다 위 |
| 온보딩 | `z-index:900–1001` | 최상위 안내 레이어 |

### 2.2 사이드바 푸터 구조

```
sidebar
  ├─ topStrip / logoRow
  ├─ newSession
  ├─ panelList
  ├─ regionArea (workspaces/sessions, flex:1, overflow:hidden)
  └─ footArea (flex column, flex:none)
       ├─ footerActions   ← sidebar.footer.action (list)
       └─ settingsArea    ← sidebar.settings (single, Settings 트리거)
```

- `sidebar.footer.action`은 **list** 슬롯이다. 여러 플러그인이 동시에 등록할 수 있다.
- `.footerActions`는 `display:flex` 한 줄이며, `gap`/`wrap`이 없다. 액션이 늘면 폭이 눌리거나 넘칠 수 있다.
- `wide` prop은 접힘 애니메이션 동안 `true`였다가 정착 후 `false`가 된다. 텍스트가 있는 컴포넌트는 150ms 동안 페이드/언마운트가 발생한다.
- **Windows Electron**: 접힘 상태에서 `[data-windows-titlebar] .collapsed .footArea { display:none }` → 푸터 액션이 **완전히 사라진다**.
- **macOS**: 접힘 상태에서 사이드바 컬럼 자체가 숨겨진다 → 푸터 액션 접근 불가.
- 우측 패널이 열리면 수동 확장 사이드바도 접힌다 → 푸터 액션이 다시 사라질 수 있다.

### 2.3 z-index 레이어

| 레이어 | z-index | 성격 |
|---|---:|---|
| 프레임 열/콘텐츠 | auto | 사이드바·중앙·우측 |
| `shell.overlay` | 20 | 프레임 전체, `pointer-events:none`, 자식만 auto |
| Windows 사이드바 토글 | 30 | 캡션 영역 고정 |
| Cordis 패널(푸터에서 열리는 fixed 패널) | 30 | 오버레이보다 위, 모달보다 아래 |
| 메뉴/팝오버 | 100 | 설정 모달 아래 |
| 설정 모달 | 1000 | 전체 화면 mask + 800px panel |
| 온보딩 | 900–1001 | 최상위 |
| 일부 portal 메뉴 | 1100 | 모달 위 |

**핵심:** `shell.overlay`(20)는 설정 모달(1000)보다 **항상 아래**다. 오버레이 안에 설정 UI를 넣으면 Settings가 열렸을 때 가려진다. 반대로 설정은 공식 모달 안(`settings.section`)에 넣어야 한다.

---

## 3. 간섭 분석

### 3.1 푸터 액션을 주 진입점으로 쓸 때의 문제

| 상태 | 발생 | 영향 |
|---|---|---|
| 사이드바 확장 | 정상 | 설정 버튼 위에 한 줄 추가, 세로 공간 소모 |
| 사이드바 접힘(56px) | `wide=false` | 라벨/상태 텍스트가 사라지고 아이콘만 남음 |
| Windows Electron 접힘 | `.footArea` display:none | **진입점 자체가 사라짐** |
| macOS 접힘 | 컬럼 숨김 | **진입점 자체가 사라짐** |
| 뷰포트 <1024 | 자동 접힘 | 위와 동일 |
| 우측 패널 열림 | 사이드바 자동 접힘 | 위와 동일 |
| 다른 플러그인 액션 추가 | footerActions flex row | 폭 경합·줄바꿈 없음·오버플로 |
| 접힘 애니메이션 | `wide` 150ms 전환 | 텍스트/패널이 깜빡이거나 잘림 |
| fixed 패널 | `left:12; bottom:56` | 사이드바 폭/본문과 겹침, 모달 뒤로 숨음 |
| z-index | 패널 30 vs 모달 1000 | 설정 모달이 열리면 패널이 가려짐 |

**판정:** 푸터는 "설정 진입점"으로 부적합하다. 특히 접힘 상태에서 사라지는 것은 알림 권한/소리 설정처럼 **한 번은 반드시 접근해야 하는 기능**에 치명적이다.

### 3.2 헤더/플로팅/모달의 문제

| 후보 | 문제 |
|---|---|
| `conversation.header` | 세션 스코프. 세션이 없으면 사라지고, 전역 알림 설정과 무관 |
| `sidebar.toggle.badge` | 접힘 상태 전용·비상호작용. 상태 점은 가능하지만 설정 진입점은 아님 |
| `shell.bottom` | 전체 폭 예약 → 콘텐츠 높이 감소. 알림 설정에는 과함 |
| `sidebar.panellist` + `main` 패널 | 대화 화면을 점유. 알림 센터로 확장할 때만 정당 |
| 우측 패널 | 무겁고 세션 문맥에 종속 |
| 고정 플로팅 배지 | 본문/작성창을 가림, 해제 불가, z-index 충돌, 라이프사이클 없음 |
| 설정 모달을 직접 띄우는 자체 모달 | 업무를 차단하고 DSH의 기존 설정과 이중화 |

### 3.3 설정 모달 안에서의 제약

- 설정 패널은 800px, 좌측 nav 188px → 콘텐츠 폭 약 612px.
- `settings.section`은 **list** 슬롯이며 `label`, `order`를 받고, 콘텐츠는 `{ close }` prop을 받는다.
- 모달 내부는 스크롤 컨테이너(`overflow-y:auto`)이므로, 섹션 콘텐츠는 자체 카드/구분선으로 구성하고 과도한 중첩 스크롤을 피한다.
- 설정 모달 자체가 z1000이므로 그 안의 UI는 오버레이 토스트/배지와 z-index 경쟁을 하지 않는다.

---

## 4. 진입점 비교와 최종 제안

| 진입점 | 지속성 | 발견성 | 접힘 영향 | 레이아웃 간섭 | z-index | 판정 |
|---|---|---|---|---|---|---|
| `settings.section` | 설정 열 때 | 높음(설정 톱니) | 없음 | 없음(모달 내부) | 1000 내부 | **주 진입점** |
| `shell.overlay` 동의 카드 | 1회 | 중간(첫 실행) | 없음 | 일시적, 우하단 | 20 | **첫 사용 전용** |
| `shell.overlay` 토스트 | 이벤트 시 | 낮음(보조) | 없음 | 일시적, 우하단 | 20 | **폴백 전용** |
| `sidebar.footer.action` | 상시 | 높음 | **사라짐** | 푸터/본문 경합 | 30 | 사용 안 함 |
| `sidebar.toggle.badge` | 접힘 시 | 낮음 | 접힘 전용 | 작은 점 | 30 | 후속 선택 |
| `conversation.header` | 세션 시 | 중간 | 세션 없으면 없음 | 헤더 경합 | 1 | 사용 안 함 |
| `shell.bottom` | 상시 | 높음 | 없음 | 높이 예약 | auto | 사용 안 함 |
| `sidebar.panellist` + main | 상시 | 높음 | 없음 | 대화 화면 점유 | auto | 알림 센터 이후 |
| 고정 플로팅 배지 | 상시 | 중간 | 없음 | 본문 가림 | 20–30 | 사용 안 함 |

**최종 제안: `settings.section` + `shell.overlay` 2면 구조.**

1. **설정 면**: `settings.section`에 `id: "notifications"`, `order: 20`, `label: "알림"`으로 등록.
   - 권한/소리 상태, 알림 종류 토글, BYO 오디오, 테스트, 데이터 초기화.
   - 사용자는 Settings 톱니 → 알림에서 모든 것을 제어한다.
2. **첫 사용 면**: `shell.overlay`에 일회성 동의 카드.
   - `Notification.permission === 'default'`이고 `consent !== 'done'`일 때만.
   - `[알림 켜기]` 클릭에서 `requestPermission()` + `AudioContext.resume()`을 **같은 사용자 제스처**로 실행.
   - `[나중에]`는 `consent='dismissed'`로 저장하고 다시 뜨지 않는다.
3. **폴백 면**: `shell.overlay`에 토스트 스택.
   - 권한 거부/미지원, 또는 `suppressWhenFocused`로 OS 알림을 생략했을 때만.
   - 최대 3개, 6초 자동 닫힘, `pointer-events:none` 컨테이너 + 카드만 auto.
4. **사이드바/헤더는 건드리지 않는다.**
   - 접힘/확장/Windows/macOS/우측 패널 상태와 무관하게 설정과 알림이 동작한다.
5. **후속 선택(필요 시)**: `sidebar.toggle.badge`에 "권한 필요" 점만.
   - 비상호작용·접힘 전용·클릭 없음. 설정 진입점으로 쓰지 않는다.

**왜 `settings.section`이 최적인가:** DSH가 이미 제공하는 공식 설정 셸을 그대로 쓰므로 레이아웃을 새로 만들지 않고, 모달 z1000 안에서 다른 UI와 충돌하지 않으며, 접힘 상태와 무관하다. 알림은 "가끔 설정하는 기능"이므로 상시 노출보다 설정 페이지가 UX상 정확하다.

---

## 5. 헤드리스 코어

### 5.1 책임 경계

| 계층 | 책임 | 금지 |
|---|---|---|
| Core | 이벤트 수신, 루트 필터, 쿨다운, 권한 상태, 오디오 로더, 설정/동의 저장, 탭 리더, 토스트 큐, 알림 발행 | React, 슬롯 이름, DOM 렌더링, CSS |
| UI adapter | 상태 구독, 버튼/폼 렌더링, 사용자 제스처 전달 | 이벤트 필터/쿨다운/저장 로직 |
| Host entry | Loader 등록용 no-op | 모든 런타임 동작 |

### 5.2 코어 API(개념)

```js
const core = createNotifyCore({
  config,                 // cordis.patch.yml 기본값
  env: {
    now, storage, notification, audio, locks, visibility, focus,
  },
  sources: {
    status(handler),      // api-session/status
    error(handler),       // api-session/error
    approval(handler),    // approval/request
    question(handler),    // user-questions/request
    session(id),          // ctx.sessions.list.getSnapshot().byId[id]
    scopeOf(scope),       // ctx.sessions.scopeOf(scope)
  },
})

core.start()
core.stop()

core.getState()           // { settings, permission, audio, leader, consent, toasts, ... }
core.subscribe(listener)  // UI 어댑터용

core.actions.requestNotifications()
core.actions.enableSound()
core.actions.test()
core.actions.setSetting(key, value)
core.actions.setByoAudio(file)
core.actions.clearByoAudio()
core.actions.dismissConsent()
core.actions.dismissToast(id)
```

- `sources`를 주입해 Cordis/DOM 없이도 Node 테스트가 가능하다.
- UI 어댑터는 `core.getState()`/`subscribe`만 사용한다.
- 코어는 `settings.section`/`shell.overlay` 같은 문자열을 **모른다.**

### 5.3 상태 스키마

```js
{
  ready: true,
  settings: {
    notifyOnComplete: true,
    notifyOnApproval: true,
    notifyOnQuestion: true,
    notifyOnError: true,
    completeCooldownMs: 5000,
    soundEnabled: true,
    volume: 0.3,
    soundSource: 'synth' | 'custom',
    suppressWhenFocused: false,
    requireInteractionForApproval: true,
    notifyOnSubagents: false,
  },
  permission: 'default' | 'granted' | 'denied' | 'unsupported',
  audio: 'locked' | 'unlocked' | 'unsupported',
  leader: true,
  consent: 'pending' | 'done' | 'dismissed',
  toasts: [{ id, kind, title, body }],
  byoAudio: { name, size, type } | null,
  lastEventAt: 0,
}
```

### 5.4 저장 전략

| 데이터 | 저장소 | 이유 |
|---|---|---|
| 설정 | `localStorage` `dsh-notify-web:settings` | 작은 JSON, 동기 접근, 탭 간 공유 |
| 동의 상태 | `localStorage` `dsh-notify-web:consent` | 1회성 플래그 |
| BYO 오디오 메타 | `localStorage` `dsh-notify-web:audio` | 이름/크기/타입/사용 여부 |
| BYO 오디오 바이트 | **IndexedDB** `dsh-notify-web/audio` | localStorage 용량 한계 회피, 바이너리 저장 |
| 오디오 캐시 | 메모리 `AudioBuffer` | 재생 지연 최소화 |

- localStorage는 문자열/용량 제한이 있으므로 오디오 바이트를 넣지 않는다.
- IndexedDB를 쓸 수 없으면 BYO 오디오는 **세션 한정**으로 동작하고, 설정 페이지에 "재시작 후 다시 선택" 안내.
- 저장 스키마에는 `schemaVersion`을 두고 마이그레이션한다.

### 5.5 오디오 로더

| 소스 | 동작 |
|---|---|
| `synth` (기본) | Web Audio oscillator 2음 차임. 에셋 없음 |
| `custom` (BYO) | 사용자가 파일 선택 → `decodeAudioData` → `AudioBuffer` 재생 |
| 실패 | synth로 자동 폴백, 설정 페이지에 짧은 안내 |
| 잠금 | `AudioContext`는 오직 사용자 제스처에서 생성/`resume` |
| 볼륨 | 0–0.5, gain envelope로 클리핑 방지 |

**BYO 오디오 라이선스:** 사용자가 선택한 파일의 권리는 사용자에게 있다. 플러그인은 파일을 번들/전송/호스팅하지 않는다.

### 5.6 탭 리더와 동기화

- Web Locks `dsh-notify-web:leader`로 한 탭만 알림 발행.
- Web Locks가 없으면 localStorage 리스(10초 TTL, 3초 갱신).
- 설정 변경은 `storage` 이벤트로 다른 탭에 전파.
- 알림 `tag`는 `dsh-notify:<sessionId>:<kind>`로 OS 수준 병합.
- 승인/질문은 `callId`/request id 기반 30초 dedupe.

### 5.7 이벤트 필터

| 이벤트 | 규칙 |
|---|---|
| `api-session/status` false | 루트 세션만, 5초 쿨다운, `running=true`에서 쿨다운 리셋 |
| `api-session/error` | 루트 세션만, 메시지 160자 |
| `approval/request` | 항상, 알림 후 즉시 `next()` |
| `user-questions/request` | 항상, 알림 후 즉시 `next()` |

- `agent/turn-stopping` 금지(serial).
- `agent/error`/`agent/status`는 브라우저 포워딩 대상이 아니므로 사용하지 않는다.
- 승인/질문 핸들러에서 `await`하지 않는다.

---

## 6. UI 어댑터

### 6.1 `settings.section` — 주 진입점

```
registration:
  name: 'settings.section'
  id: 'notifications'
  order: 20
  label: '알림'
  component: NotificationsSettings
```

콘텐츠 구성:

1. **상태 카드**
   - 브라우저 알림 권한, 오디오 상태, 이 탭의 리더 여부, 현재 origin.
   - "DSH 탭이 열려 있을 때만 알림이 동작합니다" 명시.
2. **권한/소리**
   - `브라우저 알림 켜기` → `actions.requestNotifications()`.
   - `소리 켜기` → `actions.enableSound()`.
   - `테스트 알림`.
3. **소리 소스**
   - `기본 합성음` / `사용자 오디오` 라디오.
   - `오디오 파일 선택` (`accept="audio/*"`), 파일명/크기 표시, `초기화`.
   - 라이선스 책임 안내.
4. **필터**
   - 완료/승인/질문/오류, 서브에이전트 완료, 포커스 시 완료 숨김, 쿨다운.
5. **데이터**
   - 설정 초기화, 동의 상태 초기화, BYO 오디오 삭제.
6. **정보**
   - 라이선스(MIT), "번들 에셋 없음", 버전.

**금지:** 모달 밖으로 튀는 `position:fixed` 패널, 자체 전체 화면 mask, 설정 모달과 별개의 자체 모달.

### 6.2 `shell.overlay` — 동의 카드 + 토스트

- 오버레이 레이어는 `pointer-events:none`; 카드만 `pointer-events:auto`.
- 동의 카드:
  - `role="dialog"`, `aria-modal="false"`, 제목/설명/2버튼.
  - 우하단 `right:16; bottom:16; width:min(360px, calc(100vw - 32px))`.
  - `Esc` 닫기, `나중에`와 동일하게 동의 보류.
  - 설정 모달(z1000)이 열려 있으면 카드가 뒤로 가려질 수 있음 → 카드가 보이지 않아도 설정 페이지에서 동일 기능 제공.
- 토스트:
  - 최대 3개, 6초, 같은 `tag` 교체.
  - `aria-live="polite"`.
  - `z-index`는 오버레이 레이어(20) 안에서만. 모달을 이기려 하지 않는다.
- 접근성: 포커스 트랩 없음(비모달), 키보드 닫기, 색 대비, `prefers-reduced-motion`.

### 6.3 사용하지 않는 어댑터

| 어댑터 | 이유 |
|---|---|
| `sidebar.footer.action` | 접힘/Windows/macOS에서 사라짐, 폭 경합, 설정 진입점으로 부적합 |
| `sidebar.toggle.badge` | 비상호작용·접힘 전용. 상태 점이 필요할 때만 후속 |
| `conversation.header` | 세션 스코프, 전역 설정에 부적합 |
| `shell.bottom` | 높이 예약, 레이아웃 침습 |
| `sidebar.panellist`/`main` | 대화 화면 점유. 알림 센터로 확장할 때만 |
| 고정 플로팅 배지 | 콘텐츠 가림, 해제 불가, z-index 충돌 |

---

## 7. BYO 에셋·라이선스 정책

### 7.1 기본 원칙

- 코드: **MIT** ([LICENSE](../LICENSE)).
- 패키지에 **폰트, DeepSeek 로고, 오디오 파일을 넣지 않는다.**
- 기본 아이콘은 자체 제작 중립 시계 SVG(MIT).
- 알림에는 아이콘을 지정하지 않는다(브라우저 기본).
- 기본 소리는 Web Audio 합성.
- 사용자 BYO 오디오만 선택적으로 허용하며, 라이선스 책임은 사용자에게 있다.

### 7.2 BYO 오디오 흐름

1. 설정 → 소리 소스 → `사용자 오디오` → 파일 선택.
2. 코어가 `decodeAudioData`로 디코드, IndexedDB에 저장.
3. 재생 시 `AudioBuffer` 사용. 실패하면 합성음으로 폴백.
4. `초기화`로 IndexedDB/localStorage 메타 삭제.
5. 파일은 외부로 전송되지 않는다.

### 7.3 면책

- 사용자가 주입한 폰트/아이콘/오디오의 저작권·상표권·라이선스 준수 책임은 사용자에게 있다.
- 프로젝트는 사용자 에셋을 배포/호스팅하지 않는다.
- 소프트웨어는 AS IS로 제공된다.
- 상세: [에셋·상표 라이선스 정책](2026-10-23-asset-policy.md).

---

## 8. 사용자 흐름

### 8.1 첫 설치

```
DSH 페이지 로드
  → 코어 시작 (알림 수신은 즉시)
  → 권한 default + consent pending이면 오버레이 동의 카드
      [알림 켜기] → requestPermission + AudioContext.resume (같은 제스처)
      [나중에]   → consent dismissed
  → 권한 granted면 이후 이벤트부터 OS 알림
```

- 자동 권한 프롬프트 없음.
- 동의 카드는 1회만. 이후에는 Settings > 알림에서 변경.
- 사이드바/헤더/레이아웃 변화 없음.

### 8.2 설정 변경

```
Settings 톱니 → 알림 섹션
  → 권한/소리/필터/BYO 오디오/테스트
  → 변경 즉시 localStorage 저장 + storage 이벤트로 다른 탭 전파
```

### 8.3 이벤트 발생

```
api-session/status(false) / approval / question / error
  → 코어 필터/쿨다운/리더 확인
  → 권한 granted: OS Notification + (설정 시) 소리
  → 권한 denied/unsupported: 오버레이 토스트 + (설정 시) 소리
```

- 승인/질문은 알림 후 즉시 `next()`.
- DSH 탭이 닫히면 알림 없음(설계상 한계).

### 8.4 접힘/좁은 화면/우측 패널

- 사이드바가 56px로 접히거나 사라져도 알림/설정은 그대로.
- Settings 톱니는 사이드바 하단에 고정되어 접힘 상태에서도 접근 가능(DSH 소유).
- 우측 패널 fullscreen이어도 Settings 모달은 z1000으로 접근 가능.
- 오버레이 토스트는 우측 패널 위에 잠시 표시될 수 있으나 비모달·자동 소멸.

### 8.5 다중 탭

- 리더 탭만 OS 알림/소리.
- 설정 변경은 모든 탭에 전파.
- 한 탭이 닫히면 다른 탭이 리더 승계.

---

## 9. 구현 계약

### 9.1 파일 구조(권장)

```
plugin/
  package.json
  cordis.patch.yml
  icon.svg                 # 중립 시계(MIT)
  locale/{en,ko}.json
  market/index.json
  lib/
    index.js               # no-op host
    client.js              # built bundle (DSH가 서빙)
  src/
    core.js                # 헤드리스 엔진 (React/슬롯 없음)
    ui/
      settings-section.js
      consent-card.js
      toast-host.js
    client.js              # 코어 + 어댑터 조립
  test/
    core.test.mjs
    client.test.mjs
```

- `lib/client.js`는 빌드 산출물이다. v1은 단일 파일에 코어 팩토리를 인라인해 빌드 없이 시작할 수 있지만, **코어는 React/슬롯을 import하지 않는다**는 규칙을 지킨다.
- 빌드 도구를 쓰면 `src/core.js`를 그대로 테스트하고 `lib/client.js`로 번들한다.
- `lib/index.js`는 no-op host만.

### 9.2 코어-UI 결합 금지 규칙

- 코어 파일에서 `require('react')`, `ctx.slots`, `settings.section`, `shell.overlay` 문자열 금지.
- UI 어댑터에서 `localStorage`, `Notification`, `AudioContext` 직접 접근 금지. 모두 코어 actions/state 경유.
- UI는 `core.getState()`/`subscribe`만 읽는다.
- 코어는 `sources` 주입으로 테스트한다.

### 9.3 패키지 메타

- `name: @nolit/dsh-notify-web`
- `license: MIT`
- `dsh.client.platform: 'web'`
- `dsh.client.immediately: true` (초기 이벤트 누락 최소화)
- `engines.dsh: '>=0.2.1-rc.2 <0.3.0'`
- `files`: `lib`, `src`(선택), `cordis.patch.yml`, `locale`, `market`, `icon.svg`, `README`, `LICENSE`
- `private` 없음(공개 배포 시)

### 9.4 설치

```powershell
dsh plugin --profile web add link:C:\path\to\DSH Notify\plugin
```

web 프로필의 `dsh.profile.bundles`에 `@nolit/dsh-notify-web` 추가. DSH Plugins 페이지에서 활성화.

---

## 10. 검증 계획

### 10.1 레이아웃·z-index 매트릭스

| # | 상태 | 기대 |
|---|---|---|
| V1 | 1440px, 사이드바 확장 | 설정 섹션 정상, 사이드바 변화 없음 |
| V2 | 1024px 경계 | 자동 접힘과 무관하게 알림 동작 |
| V3 | 768px, 사이드바 레일 | 설정은 Settings 모달에서 정상 |
| V4 | 480px | 동의 카드/토스트가 뷰포트 밖으로 나가지 않음 |
| V5 | Windows Electron 접힘 | 푸터 없음, 알림/설정 정상 |
| V6 | macOS 접힘(컬럼 숨김) | 알림/설정 정상 |
| V7 | 우측 패널 열림/전체화면 | 오버레이 토스트가 프레임 안, 설정 모달 정상 |
| V8 | Settings 모달 열림 | 설정 섹션 스크롤/포커스 정상, 토스트는 모달 뒤 |
| V9 | 다크/라이트 | 대비/토큰 정상 |
| V10 | 다중 탭 | 리더 1개, 설정 동기화 |
| V11 | 권한 granted/denied/default | Notification/토스트 분기 |
| V12 | 오디오 잠금/언락/BYO 실패 | 합성음 폴백, 무예외 |

### 10.2 회귀

- `docs-contract` 통과.
- 기존 앱 테스트 19/19는 앱 코드 무변경이므로 영향 없음.
- 웹 플러그인 단위 테스트: 이벤트 필터/쿨다운/승인 `next()`/권한 폴백/리더/설정 저장/BYO 오디오 폴백.

### 10.3 금지 패턴 검사

- `sidebar.footer.action` 문자열이 최종 `client.js`에 없어야 한다.
- `position:fixed` 설정 패널이 `settings.section` 밖에 없어야 한다.
- `fetch`/`XMLHttpRequest`/`WebSocket`/`EventSource` 신규 사용 없음.
- `localStorage` 접근은 코어에만.
- `agent/turn-stopping` 구독 없음.

---

## 11. 리스크·결정

| 리스크 | 영향 | 완화 |
|---|---|---|
| Settings 섹션 발견성 | 사용자가 설정 위치를 모를 수 있음 | 첫 실행 동의 카드에 "Settings > 알림" 안내, 테스트 버튼 |
| 동의 카드가 설정 모달 뒤로 숨음 | 첫 실행 직후 Settings를 열면 카드 안 보임 | 설정 페이지에 동일 버튼 제공, 카드 1회성 |
| 오버레이 토스트가 모달 뒤로 숨음 | 권한 거부 + Settings 열림 시 토스트 미표시 | OS 알림이 primary, 토스트는 보조. 모달 중에는 조용히 무시 |
| BYO 오디오 저장 실패 | IndexedDB 불가/쿼터 | 세션 한정 재생, 합성음 폴백, 안내 |
| 브라우저 자동재생 정책 | 첫 소리 무음 | 사용자 제스처에서만 AudioContext, 상태 표시 |
| 알림 권한 출처 종속 | 포트 변경 시 재승인 | 설정 페이지에 현재 origin/권한 표시 |
| DSH API 변경 | 슬롯/이벤트 깨짐 | `engines.dsh` 고정, 이벤트 4종 테스트, 플러그인 내부 격리 |
| 다중 탭 리더 경합 | 일시 중복/누락 | Web Locks + 폴백 리스 + `tag` |
| 사용자 에셋 라이선스 | 법적 분쟁 | 번들 없음 + 면책 + MIT |

### 확정 필요

| # | 결정 | 권장 |
|---|---|---|
| 1 | 주 설정 진입점 | `settings.section` |
| 2 | 첫 사용 동의 | `shell.overlay` 일회성 카드 |
| 3 | 사이드바 푸터 | 사용 안 함 |
| 4 | BYO 오디오 저장 | IndexedDB(바이트) + localStorage(메타) |
| 5 | 기본 소리 | Web Audio 합성 |
| 6 | 상태 배지 | v1 없음, 필요 시 `sidebar.toggle.badge` 점만 |
| 7 | v1 범위 | 설정 섹션 + 동의 카드 + 토스트 + 코어 |

---

## 부록: 이전 초안에서 폐기할 것

- `sidebar.footer.action`에 배지/패널을 붙이는 방식.
- 푸터 버튼에서 `position:fixed` 패널을 여는 방식.
- UI 컴포넌트 안에 `localStorage`/`Notification`/`AudioContext` 로직을 두는 방식.
- 설정 모달 밖에 별도 설정 모달을 띄우는 방식.
- 사이드바 접힘 상태를 고려하지 않은 고정 좌표(`left:12; bottom:56`).
- `wide` prop 텍스트에 의존하는 상태 표시.

이 보고서를 기준으로 다음 단계에서 코어 → 설정 섹션 → 동의 카드/토스트 순서로 구현한다.
