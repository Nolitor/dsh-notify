# DSH 하네스 알림 — 기능 스펙

> 상태: draft · 최종 갱신: 2026-10-20 · git: main @ milestone-2 · 상위: [2026-10-20-dsh-notify-design.md](2026-10-20-dsh-notify-design.md)

DSH(DeepSeek Harness) 작업이 끝났거나, 사람의 승인·답변이 필요할 때 Windows 우하단 알림을 띄운다. **포트·웹서버·데몬 없이** OS 알림 API만 호출한다.

## 인덱스

| § | 섹션 | 이동 | 한 줄 요약 |
|---|---|---|---|
| 1 | 원칙 | [§1](#1-원칙) | 프로세스 1회 호출 + OS 토스트, 서버 없음 |
| 2 | 이벤트 | [§2](#2-이벤트) | 확인된 host event 6종, 금지 1종 |
| 3 | 전달 | [§3](#3-전달) | 플러그인 → `send-toast.ps1` 프로세스 호출 |
| 4 | 표시 | [§4](#4-표시) | ToastGeneric, PS7→5.1 위임, AUMID |
| 5 | 정책·설정 | [§5](#5-정책설정) | 종류별 on/off, 합치기, 시작 억제 |
| 6 | 한계 | [§6](#6-한계) | 클릭 미지원, Focus Assist, Win10+ |
| 7 | 검증 | [§7](#7-검증) | tests\toast.ps1 + 수동 스모크 |
| 8 | 세션 시작 피크 알림 | [§8](#8-세션-시작-피크-알림) | notify\peak-alert.ps1 |

---

## 1. 원칙

- 로컬 웹서버·포트·파일 스풀·상주 IPC를 두지 않는다.
- 이벤트는 사람 속도(초~분)이므로 **이벤트당 프로세스 1회 호출**로 충분하다(실측 약 1.5초, 비동기 fire-and-forget).
- 알림 실패가 하네스를 방해하면 안 된다. 플러그인은 호출 결과를 기다리지 않고 출력도 버린다.
- 판정 계층(피크 인디케이터, 60초 폴링)과 알림 계층(사건 푸시)은 분리한다.

## 2. 이벤트

DSH Host 가 노출하는 이벤트 중 **emit 모드**만 사용한다. (2026-10-20 Inspect 로 확인)

| 이벤트 | 의미 | 모드 | 알림 |
|---|---|---|---|
| `approval/request` | 도구 승인 대기 | waterfall (관찰만, `next()` 그대로) | 승인 필요 |
| `user-questions/request` | 모델이 선택지 질문 | waterfall (관찰만) | 답변 필요 |
| `agent/status` | `running` ⇄ `idle` | emit | 작업 완료 |
| `api-session/status` | 세션 running 변화 | emit | 완료 판정 보조 |
| `agent/error` | 스텝/턴 오류 | emit | 실패 |
| `deepseek-account/model-sign-in-required` | 재로그인 필요 | emit | 로그인 |

**금지**: `agent/turn-stopping`. serial(awaited) 이므로 리스너가 턴 종료를 지연시킬 수 있다.

## 3. 전달

```
DSH host plugin  ──spawn──▶  pwsh -Sta -File notify\popup.ps1 -Title .. -Body ..
                                   │
                                   └─▶ WPF 다크 팝업 (화면 우하단, 6초, 클릭 닫기)
```

- 포트도, 소켓도, 폴링도 없다.
- 기각한 대안: ① 로컬 HTTP 엔드포인트(포트 추가) ② 파일 스풀 폴링(데몬 필요) ③ 상주 named pipe(수명·재시작 복잡도).
- 플러그인은 세션 제목/작업 폴더와 이벤트 종류만 본문에 넣는다. 프롬프트 원문·토큰·코드 내용은 넣지 않는다.
- **왜 윈도 토스트가 아니라 자체 팝업인가**: 토스트는 OS 가 "delivered" 로 기록해도 집중 지원·전체화면 등에서 배너가 억제되고, 앱 쪽에서는 표시 여부를 알 수 없다. DSH Notify 는 WPF 창으로 직접 그려 확실히 보이게 한다. `notify\toast.ps1`/`send-toast.ps1` 은 수동 확인용으로 남긴다(브리지는 popup.ps1 이 있으면 그것을 우선 사용).
- **알림음: 사용 안 함(2026-10-20 결정)**. 이 PC에서는 WinMM·5.1 WinRT 자식 경로가 스피커 앰프까지 도달하지 않았고(피크 0), 미디어 플레이어를 경유하면 창이 떠서 알림 UX가 망가졌다. DSH 이벤트 알림은 **팝업만** 표시한다. 관련 코드(`play-wav.ps1`, ding.wav)는 수동 실험용으로만 남긴다.
- **스폰 방식**: 전달은 `cache\popup-request.json` 큐로 바꿨다. 브리지는 파일만 원자적으로 쓰고, 상주 코어(`core.ps1`)가 1초 tick 에서 집어 **자기 프로세스에서** 팝업과 소리를 처리한다. 스폰된 자식 프로세스의 소리는 이 환경에서 잘렸다(실측) — 코어 경로는 내부 테스트와 동일해서 정상 재생된다. 파일 큐가 없으면 popup.ps1 스폰으로 폴백한다.

### 3.1 구현 (bridge)

- 코드: `bridge\` — ESM host 플러그인 `@local/dsh-notify-bridge` (`index.js`)
- 등록: 프로필 `~\.dsh\profiles\desktop\node_modules\@local\` 에 junction + `cordis.patch.yml` 의 `insert` 엔트리
- 이벤트 매핑

| 이벤트 | 알림 | 비고 |
|---|---|---|
| `api-session/status` running=false | `DSH 작업 완료` | 세션별 5초 쿨다운 |
| `approval/request` | `DSH 승인 필요` | waterfall — `next()` 그대로 통과 |
| `user-questions/request` | `DSH 질문 대기` | waterfall |
| `agent/error` | `DSH 오류` | 오류 메시지 160자 |

- 설정(`cordis.patch.yml`): `notifyRoot`, `onComplete/onApproval/onQuestion/onError`, `completeCooldownMs`, `debugLog`
- **알림 스위치**: 이벤트마다 `config.json` 의 `notifications` 를 읽어 꺼져 있으면 조용히 넘긴다. 트레이 메뉴 `알림` 체크가 이 값을 토글한다
- **서브에이전트 필터**: 완료 알림은 `agents.roots()` 에 포함된 세션에서만 띄운다. 승인/질문은 서브에이전트 것이어도 사람이 결정해야 하므로 그대로 알린다
- **스코프 이벤트**: `agent/status`·`agent/error` 등은 `Scoped<Agent>` 라서 기본 리스너에는 오지 않는다. `ctx.on(event, handler, { global: true })` 로 등록해 범위 필터를 우회한다(실측: `tools/result` 프로브로 확인). 데스크톱 프로필에는 `api-session` 플러그인이 없어 `api-session/status` 는 발생하지 않는다 → 완료 신호는 **`agent/turn-stopping`(serial, 즉시 반환) + `agent/status` idle** 을 함께 사용
- 세션 필터는 객체 동일성이 아니라 **`roots().some(r => r.id === sessionId)`** 로 비교한다
- 로더가 patch 변경을 감지해 **재시작 없이 적용**된다. 적용 증거는 `cache\bridge.log` 한 줄(`bridge 0.3.6 applied: …`)
- 롤백: `cordis.patch.yml.bak` 복원 + junction 삭제

## 4. 표시

- `notify\toast.ps1` — `New-ToastXml`(순수) + `Send-WindowsToast`(5.1 필요)
- `notify\send-toast.ps1` — CLI. **PS7 은 WinRT 타입을 직접 로드할 수 없다(실측 실패)** → Windows PowerShell 5.1 자식 프로세스로 자기 자신을 재실행해 표시한다. `-DryRun` 은 XML 만 출력.
- **인코딩**: 5.1 이 직접 파싱하는 `notify\*.ps1` 은 **UTF-8 BOM 필수**. BOM 이 없으면 5.1 이 ANSI 로 읽어 한글 리터럴이 깨진다(실측: 첫 스모크에서 깨진 글자 표시). `tests\encoding.ps1` 이 강제한다.
- 기본 `AppId` 는 Windows PowerShell AUMID(실측 표시 성공). 앱 이름·아이콘을 "DSH Notify" 로 바꾸려면 시작메뉴 바로가기 + AUMID 등록이 필요하다 → v1 범위 밖.
- 토스트 이력은 Windows 알림 센터에 남는다 → 민감 정보는 본문에 넣지 않는다.

## 5. 정책·설정

```json
"notify": {
  "turnEnd": true,
  "approval": true,
  "question": true,
  "error": true,
  "coalesceSeconds": 5
}
```

- 같은 종류·같은 세션의 알림이 `coalesceSeconds` 안에 겹치면 1회로 합친다.
- 앱 시작 직후 첫 이벤트는 억제(켤 때마다 울리지 않게).
- `turnEnd` 는 `agent/status` 의 `idle` 전환에서만 발생시킨다(중간 스텝 제외).

## 6. 한계

- **클릭 동작 없음**: 토스트 클릭으로 GUI 를 열려면 COM activator 등록이 필요하다. v1 은 표시 전용. 클릭이 필요하면 AUMID+COM 등록 또는 트레이 앱 풍선으로 승격.
- Windows 10/11 전용. Windows 7/8 은 토스트 미지원(트레이 풍선으로 폴백 필요).
- Focus Assist·방해 금지 시간에는 표시되지 않을 수 있다.
- VPN 이 아닌 로컬 OS 알림이므로 네트워크 의존은 없다.

## 7. 검증

- `tests\toast.ps1` — XML 4케이스(템플릿·이스케이프·빈 본문·재파싱) + CLI dry-run 2케이스.
- `tests\encoding.ps1` — 5.1 실행 스크립트 BOM 검사.
- `tests\peak-alert.ps1` — 피크 경고 4케이스.
- 수동 스모크(2026-10-20): `send-toast.ps1` 실행 → 우하단 토스트 표시, exit 0, 약 1.5초.
  BOM 적용 전 임시 스크립트가 한글을 깨뜨린 사례도 이때 확인했다.
- `node bridge\test.mjs` — 완료 1회·쿨다운, turn-stopping, 승인/질문 `next()` 통과, 오류 문구, `ctx.on` 등록.
- `tests\popup.ps1` — dry-run 기하/문구, BOM.
- 프로필 적용 확인: `cache\bridge.log` 에 `bridge 0.4.0 applied: ...` 1줄. 로더 핫 리로드로 재시작 없이 붙는다.

## 8. 세션 시작 피크 알림

하네스 세션이 시작될 때 "지금 피크" 를 바로 알린다. 판정은 기존 provider 를 그대로 쓴다.

```powershell
# 피크일 때만 표시 (오프피크면 조용히 종료)
notify\peak-alert.ps1

# 미리보기: 실제 팝업 없이 XML 만
notify\peak-alert.ps1 -DryRun

# 오프피크여도 강제로 표시 (수동 확인용)
notify\peak-alert.ps1 -Force
```

- 제목/본문: `지금 PEAK · 100%` + `딥시크 피크 구간입니다 (100%). … → 다음 구간까지 2h 00m`
- 연결 지점: DSH 플러그인이 세션 시작(`agent/created` 또는 `session/created`, emit) 에서 1회 호출.
  턴마다 부르면 시끄러우므로 세션 시작 기준으로 둔다.
- 오프피크에는 아무 출력도 내지 않는다(침묵이 기본). `-Force` 는 수동 점검용.
