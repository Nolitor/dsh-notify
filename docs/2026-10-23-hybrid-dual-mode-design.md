# DSH Notify 하이브리드 듀얼 모드 — 실측 및 아키텍처 설계 보고서

> 상태: proposed · 최종 갱신: 2026-10-23 · git: main @ 70a6606 · 상위: [README.md](../README.md)

- 목적: DSH Notify를 **독립 윈도우 상주 앱 + DSH 브라우저 플러그인**의 하이브리드 듀얼 모드로 전환하기 전, 현재 상태를 실측하고 구현 계약을 확정한다.
- 범위: 1단계 환경·프로젝트 실측, 2단계 환경 독립성·동적 바인딩·듀얼 브리지 설계, 단계별 로드맵.
- 이번 단계에서 **코드와 기존 파일은 수정하지 않았다.** 추가된 것은 이 보고서 1개뿐이다.
- 실측 시점: 2026-10-23 03:30 KST (Asia/Seoul).

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 결론 요약 | 현재는 듀얼 모드가 아니며, 호스트 하프 경유 + 가변 포트 + 브라우저 폴백이 정답 |
| 2 | 1단계 실측 | 구조·실행 환경·기존 타이머/알림·배포 현실·경로 결합·테스트 기준선 |
| 3 | 요구 대비 격차 | 6개 요구사항별 현재/목표/격차 |
| 4 | 2단계 설계 | 컴포넌트·이벤트·포트·경로·라이프사이클·보안·설정 |
| 5 | 단계별 로드맵 | Phase 0–5, 산출물·검증·종료 조건·예상 공수 |
| 6 | 수용 기준 | 포트/경로/폴백/중복/보안/회귀 검증 매트릭스 |
| 7 | 위험 등록부 | 기술·운영·보안 위험과 완화 |
| 8 | 미결 결정 | 권장 기본값과 결정이 필요한 항목 |
| 9 | 부록 | 프로토콜 예시, 데이터 배치, 검증 명령 |

---

## 1. 결론 요약

**현재 DSH Notify는 하이브리드 듀얼 모드가 아니다.** 실체는 다음 세 가지다.

1. `core.ps1` 단일 WPF 상주 프로세스가 60초마다 피크/오프피크를 판정하고 카드·트레이를 갱신한다.
2. DSH 이벤트 브리지(`bridge/index.js`)는 **desktop 프로필에만** 등록되어 있고, 이벤트를 `cache/popup-request.json` 파일로 남기면 코어가 1초 tick에서 집어 팝업을 띄운다.
3. **현재 실행 중인 DSH는 `dsh web --port 3080`(web 프로필)이며, web 프로필에는 브리지가 없다.** 따라서 지금 이 GUI에서 작업을 끝내도 DSH Notify 팝업은 뜨지 않는다. 이번 전환의 가장 큰 실질 격차다.

권장 구조는 다음과 같다.

```
[DSH Web 브라우저]                         [DSH Host(Node)]                    [DSH Notify 앱(PowerShell/WPF)]
 client half ── same-origin POST ──▶ host half ── loopback HTTP ──▶ listener
   │  이벤트 감지/리더/폴백                    │  포트 탐색/토큰/프록시              │  팝업·트레이·타이머
   └─ Web Notification + Web Audio ◀── 결과( delivered / unavailable ) ────────────┘
```

핵심 판단 5가지:

| # | 판단 | 근거 |
|---|---|---|
| D1 | **브라우저가 앱 포트를 직접 찾게 하지 않는다.** DSH 플러그인의 **host half**가 같은 출처 `/api/local/dsh-notify/*` 라우트로 받아 앱에 프록시한다. | 브라우저는 `%LOCALAPPDATA%`를 읽을 수 없고, 가변 포트 탐색·CORS·HTTPS 페이지의 mixed content·토큰 노출 문제를 모두 피할 수 있다. |
| D2 | 앱은 **포트 0(ephemeral)** 으로 바인딩하고 `%LOCALAPPDATA%\DSH Notify\runtime.json`에 포트·토큰·PID를 원자적으로 쓴다. | 포트 충돌이 원천적으로 없고, 사용자명·고정 포트 하드코딩이 사라진다. |
| D3 | **오디오는 브라우저가 소유**한다(데스크톱 팝업이 떠도 브라우저가 재생). | 이 PC에서 WinMM/WinRT/미디어 플레이어 경로의 앱 오디오가 실패했다는 기존 실측이 있다. 브라우저 `<audio>`/Web Audio만 검증된 경로다. |
| D4 | 완료 알림은 **`api-session/status`(running=false)** 를 정본으로 쓴다. | web 프로필에는 `api-session`이 있고, 이 이벤트는 브라우저로 전달된다. `agent/turn-stopping`은 serial이라 금지한다. |
| D5 | 설치 대상은 **web 프로필**이다. desktop 브리지는 검증 완료 전까지 병행 유지한다. | 현재 DSH GUI가 web 프로필이므로, desktop만 고치면 이번 요구를 충족하지 못한다. |

**타당성 판정: 구현 가능. 차단 요소 없음.** 다만 아래 두 가지는 설계에 반영해야 한다.

- DSH 브라우저 플러그인의 클라이언트 이벤트는 **전달 허용 목록**에 묶여 있다. `agent/error`는 브라우저로 오지 않으므로 `api-session/error`를 써야 한다.
- 알림 권한과 오디오 언락은 **출처(origin) 단위**다. DSH 포트가 바뀌면 `http://127.0.0.1:3080`과 `:3081`은 다른 출처가 되어 권한을 다시 받아야 한다. 따라서 "포트가 바뀌어도 코드 수정 없이 동작"과 "권한 재승인"은 별개로 설계해야 한다.

---

## 2. 1단계: 로컬 환경 및 기존 프로젝트 실측

### 2.1 프로젝트 구조와 진입점

루트: `C:\Users\nolit\Workspace\projects\DSH Notify` (git `main`, HEAD `70a6606`, 실측 시점 clean).

| 구분 | 파일/디렉터리 | 역할 | 실측 메모 |
|---|---|---|---|
| 앱 진입점 | `core.ps1` | WPF 상주 프로세스. 단일 인스턴스, 60초 poll, 1초 tick | 494줄. `pwsh -Sta` 필수 |
| 앱 실행 | `start.ps1` | `core.ps1`을 숨김 `pwsh -Sta`로 재실행 | `$PSScriptRoot` 기반, 이식성 양호 |
| 앱 실행(레거시) | `start.vbs` | VBScript로 숨김 실행 | 이 PC는 VBScript 엔진이 꺼져 있어 비권장 |
| 설정 | `config.ps1` | `config.json` 로드/병합/원자적 저장 | 기본값·손상 강등·좌표 클램프 포함 |
| 판정 | `providers/deepseek-peak.ps1` | 피크/오프피크, 공휴일 캐시, 지역 보정 | 네트워크는 공휴일/지역만. 판정은 UTC 고정 |
| UI | `ui/indicator.ps1`, `ui/presenter.ps1`, `ui/tray.ps1`, `ui/popup.ps1` | 카드·표시 모델·트레이·인프로세스 팝업 | 팝업은 코어 프로세스에서 직접 표시 |
| DSH 브리지 | `bridge/index.js` | desktop 프로필 host 플러그인 | **파일 큐 방식**, 고정 루트 하드코딩 |
| 브리지 패키지 | `bridge/package.json` | `@local/dsh-notify-bridge` | 루트에는 `package.json` 없음 |
| 알림 CLI | `notify/popup.ps1`, `notify/send-toast.ps1`, `notify/toast.ps1` | 수동/폴백 팝업·토스트 | 토스트는 집중 지원에서 배너 억제 가능 |
| 빌드 | `build/build-exe.ps1` | 단일 exe 래퍼 | `%LOCALAPPDATA%\DSH Notify\runtime`에 압축 해제 |
| 테스트 | `tests/*.ps1`, `bridge/test.mjs` | 19개 PowerShell + Node 단위 | 기준선 전부 통과 |
| 문서 | `docs/*.md` | 설계·스펙·마감 상태 | 문서 계약 검사 48파일 통과 |

**의존성:** 앱은 PowerShell 7 + .NET/WPF/Windows Forms 외 외부 패키지가 없다. Node 의존성은 `bridge`에만 있고, 실제로는 `node:child_process`, `node:fs`, `node:path`만 쓴다. 루트 `package.json`, lockfile, 번들러는 없다.

**기존 타이머/알림 구현 방식:**

```
providers/deepseek-peak.ps1  ──60초──▶ core.ps1 Invoke-Poll
                                      ├─ Get-State (공휴일 캐시, 지역 보정)
                                      ├─ Test-NotifyTransition (severity 변화 시 1회)
                                      ├─ Save-NotifyState (원자적)
                                      └─ Update-Ui (카드/트레이)
core.ps1 1초 tick ──▶ Update-Ui + Invoke-PopupRequests
                                      └─ cache/popup-request.json 소비 → Show-NotifyPopup
```

- 단일 인스턴스: `Local\DSHNotify` 뮤텍스(`core.ps1:48`).
- 데이터 경로: `$PSScriptRoot\config.json`, `$PSScriptRoot\cache\`(`core.ps1:55-60`). 즉 **코드와 데이터가 같은 프로젝트 폴더**에 있다.
- 팝업: `cache/popup-request.json`을 1초마다 폴링(`core.ps1:213-227`). 포트·소켓·HTTP 없음.
- 브리지: 이벤트 발생 시 파일만 원자적으로 쓰고, 코어가 소비한다. 자식 `pwsh` 스폰 폴백도 있으나 현재는 파일 큐가 우선(`bridge/index.js:45-85`).

### 2.2 실행 환경

| 항목 | 실측값 | 비고 |
|---|---|---|
| OS | Windows 11 Home, 10.0.26300, AMD64 | Windows 10/11 계열 |
| PowerShell | 7.6.7 (Core) | `-Sta` WPF, `Start-ThreadJob` 사용 가능 |
| Node | v24.19.0 | DSH 요구 `>=24`, 전역 `fetch`/`AbortSignal.timeout` 사용 가능 |
| npm | 11.17.0 | |
| pnpm | 10.34.7 | DSH 프로필 패키지 관리 |
| yarn | 없음 | 사용하지 않음 |
| DSH CLI | 0.2.1-rc.2 | `@deepseek-ai/dsh` 전역 npm 설치 |
| DSH 실행 | `dsh web --port 3080` | PID 54728, `127.0.0.1:3080` LISTEN |
| DSH 홈 | `C:\Users\nolit\.dsh` | web/desktop 프로필 존재 |
| DSH GUI | `http://127.0.0.1:3080` | 무토큰 루트는 401(인증 필요) |
| 앱 실행 | PID 60332, `core.ps1` | 프로젝트 폴더에서 실행 중 |
| 앱 데이터 | `%LOCALAPPDATA%\DSH Notify` **없음** | 현재 설정/캐시는 프로젝트 폴더 사용 |
| 테스트 | 19 files / 19 passed, bridge 통과, docs 48 통과 | 기준선 확보 |

**중요:** `DSH-Notify.exe`(125,952 bytes)는 이 PC의 Smart App Control 정책으로 실행이 차단된다. 배포·자동 시작은 당분간 **시작 메뉴 바로가기 + `pwsh` 스크립트**가 현실적이다. 새 설계도 exe를 전제로 하지 않는다.

### 2.3 현재 DSH 브리지의 실제 결합 상태

**브리지는 desktop 프로필에만 있다.**

- `C:\Users\nolit\.dsh\profiles\desktop\cordis.patch.yml:421-430`에 `dsh-notify-bridge` insert 엔트리와 절대경로 `notifyRoot`, `debugLog`가 있다.
- `C:\Users\nolit\.dsh\profiles\web\cordis.patch.yml`에는 `dsh-notify` 관련 엔트리가 **없다**.
- 현재 `dsh web --port 3080`은 **web 프로필**을 부팅한다. 따라서 현재 GUI 세션에서는 브리지가 로드되지 않는다.
- `cache/bridge.log`의 마지막 적용 기록은 `2026-10-21T08:59:10`이며, 이후 이벤트 기록이 없다. 이는 web 프로필에 브리지가 없기 때문으로 해석된다.

**브리지 코드의 고정 경로:**

| 위치 | 내용 | 문제 |
|---|---|---|
| `bridge/index.js:22` | `const DEFAULT_ROOT = 'C:\\Users\\nolit\\Workspace\\projects\\DSH Notify'` | 사용자명·절대경로 하드코딩 |
| `bridge/README.md:15,21` | `notifyRoot`, `debugLog`에 `C:/Users/nolit/...` 예시 | 문서가 특정 계정에 결합 |
| `desktop/cordis.patch.yml:424,430` | 동일 절대경로 | 프로필이 머신에 결합 |
| `docs/2026-10-20-dsh-notify-design.md:7` | 프로젝트 루트 절대경로 | 역사 문서(구현 시 갱신 대상) |
| `docs/BOOT-CARD.md:33` | 동일 | 역사 문서 |

앱 코드 자체는 `$PSScriptRoot` 기반이라 이식성이 좋다. 문제는 **데이터 루트가 프로젝트 폴더**라는 점, 그리고 **브리지/프로필의 절대경로**다.

### 2.4 기존 이벤트 매핑과 한계

현재 브리지(`bridge/index.js`)의 핸들러:

| 이벤트 | 동작 | 비고 |
|---|---|---|
| `api-session/status` (running=false) | `DSH 작업 완료` | 세션별 5초 쿨다운 |
| `agent/status` (idle) | 완료 보조 | 객체 id 비교로 루트 판별 |
| `agent/turn-stopping` | 완료 | **serial 이벤트** — 스펙에서는 금지(`docs/dsh-harness-notify-spec.md:42`) |
| `approval/request` | `DSH 승인 필요` | waterfall, `next()` 통과 |
| `user-questions/request` | `DSH 질문 대기` | waterfall, `next()` 통과 |
| `agent/error` | `DSH 오류` | 오류 메시지 160자 |

**모순:** 스펙은 `agent/turn-stopping`을 금지하지만, desktop 프로필에는 `api-session`이 없어 완료 신호를 잡기 위해 브리지가 이를 사용했다. **web 프로필에는 `api-session`이 있으므로, 새 설계에서는 `api-session/status`만 정본으로 쓰고 `agent/turn-stopping`을 제거한다.** 이는 턴 종료 지연 위험을 없앤다.

### 2.5 DSH 브라우저 플러그인 API 실측 (핵심)

DSH 0.2.1-rc.2의 설치본에서 확인한 공개 확장점:

| API | 확인 내용 | 설계 사용 |
|---|---|---|
| `package.json`의 `dsh.client` | `platform: 'web'`, `inject`(정보성 패키지 목록), `immediately`, `external` | 패키지가 브라우저 번들을 제공 |
| `/plugins` | host가 `lib/client.js`를 번들로 서빙 | `dsh.client` 선언만으로 로드 |
| `ctx.remote.$on(event, fn)` | 전달 허용 목록의 Host 이벤트 구독 | `api-session/status`, `api-session/error`, `approval/request`, `user-questions/request` |
| `ctx.connection.fetch.register({path,methods,requestBody,fetch})` | `/api` 아래 exact Fetch 라우트. owner Peer만 도달 | `/api/local/dsh-notify/*` |
| `ctx.sessions.list.getSnapshot()` | 세션 목록(`byId`, `parentId`, `origin`) | 루트 세션 필터 |
| `ctx.slots` | React 슬롯 UI | 상태 배지/인페이지 토스트 |
| `dsh.client.inject` vs `exports.inject` | 전자는 패키지 의존성 메타, 후자는 Cordis 서비스 주입 | 둘을 혼동하지 않는다 |

**브라우저로 전달되는 이벤트(설치본 `dsh-api-remotes`의 허용 목록):**

- `api-session/status` — `(sessionId, running)`
- `api-session/error` — `(sessionId, message)`
- `approval/request` — waterfall
- `user-questions/request` — waterfall
- 그 외 `api-session/added|removed|activity`, `permission-presets/catalog-changed` 등

**브라우저로 전달되지 않는 이벤트:**

- `agent/error` — 현재 브리지가 쓰는 이벤트지만 **클라이언트 허용 목록에 없다.** 브라우저에서는 `api-session/error`를 써야 한다.
- `agent/status`, `agent/turn-stopping` — 클라이언트 허용 목록에 없다.

**클라이언트 세션 상태 구현 선례:** `dsh-client-ui-session`은 `ctx.remote.$on("api-session/status", ...)`로 running 상태를 갱신한다(`lib/client.js:814`). 승인 UI는 `ctx.remote.$on("approval/request", function(request,next){...})`로 요청을 관찰하고 `next()`를 넘긴다(`dsh-client-ui-approval/lib/client.js:355`). 새 플러그인도 같은 패턴을 쓸 수 있다.

**HMR/빌드:** host는 빌드된 `lib/client.js`를 서빙한다. 소스 체크아웃에서 자동 리로드는 `pnpm run dev:web`이 필요하다. 이 프로젝트는 DSH 체크아웃 밖에 있으므로, v1은 **손으로 작성한 module-loader CJS 번들**(`dsh-sidebar-manager` 선례)로 빌드 단계를 없애는 것이 단순하다. 파일 수정 후에는 페이지 새로고침 또는 DSH 재시작을 기본으로 본다.

### 2.6 현재 테스트 기준선

| 명령 | 결과 |
|---|---|
| `pwsh -NoProfile -File tests\run-all.ps1` | **19 files, 19 passed, 0 failed** |
| `node .\bridge\test.mjs` | **bridge tests passed** |
| `pwsh -NoProfile -File tests\docs-contract.ps1` | **48 file(s) PASS** |

새 설계는 이 기준선을 깨지 않아야 한다. 특히 `docs-contract`는 새 문서에 `> 상태:` 헤더와 `## 인덱스`를 요구한다.

### 2.7 제약과 알려진 문제(설계 입력)

| 제약 | 내용 | 설계 영향 |
|---|---|---|
| 앱 오디오 실패 | WinMM/WinRT/미디어 플레이어 경로가 스피커까지 도달하지 못했다(기존 실측). 현재 팝업은 무음 | 오디오를 브라우저가 소유 |
| 토스트 배너 억제 | 집중 지원/알림 설정에서 배너가 숨겨질 수 있고 앱이 표시 여부를 모른다 | 자체 WPF 팝업 유지, 토스트는 보조 |
| SAC | 서명 없는 exe 차단 | exe 의존 금지, 바로가기/스크립트 유지 |
| 로그 무한 증가 | `core.log`, `bridge.log` 로테이션 없음 | 새 로그는 크기 기반 로테이션 |
| VBScript | 이 PC에서 엔진 꺼짐 | `start.ps1` 유지 |
| DSH 포트 가변 | `--port`로 변경 가능 | 출처 기반 동작 + 권한 재승인 UX |
| 브라우저 권한 | Notification/Audio는 출처 단위, 사용자 제스처 필요 | 인페이지 "알림/소리 켜기" 배너 |
| 원격 DSH | DSH가 원격 서버면 host half가 사용자 PC의 앱에 접근 불가 | 동일 PC 가정, 원격은 브라우저 폴백만 |

---

## 3. 요구 대비 격차

| 요구 | 현재 | 목표 | 격차 |
|---|---|---|---|
| 1. 포트 가변성 | 포트 없음(파일 큐). DSH 포트는 어디에도 기록 안 됨 | 플러그인이 `window.location.origin`을 사용하고, 앱은 ephemeral 포트 | 앱 리스너·디스크립터·프로토콜 신규 |
| 2. 경로 추상화 | 앱 데이터=프로젝트 폴더, 브리지=`C:\Users\nolit\...` 하드코딩 | `%LOCALAPPDATA%` + `os.homedir()` + 패키지 상대경로 | 데이터 루트 분리, 마이그레이션 필요 |
| 3. 독립 상주 앱 | 이미 독립 실행·타이머·트레이 동작 | 부팅 시 단독 실행, 로컬 신호 대기 | 리스너 추가만. 타이머는 그대로 |
| 4. DSH 웹 플러그인 | web 프로필에 없음. desktop 브리지만 존재 | web 프로필에 host+client 하프 패키지 | 패키지·프로필 설치 신규 |
| 5. 로컬 앱 핑 | 파일 큐(1초 폴링) | same-origin 라우트 → loopback HTTP 즉시 전달 | 전달 계층 교체 |
| 6. 브라우저 폴백 | 없음(파일 큐가 없으면 popup 스폰) | Web Notification + Web Audio + 인페이지 토스트 | 클라이언트 UI/오디오 신규 |

**총평:** 앱의 타이머·판정·트레이 자산은 그대로 재사용할 수 있다. 새로 만드는 것은 ① 앱의 로컬 리스너/디스크립터, ② DSH 플러그인의 host half, ③ 브라우저 half의 이벤트·폴백 UI다. 기존 파일 큐는 폐기 대상이지만, 마이그레이션 기간에는 병행 가능하다.

---

## 4. 2단계: 환경 독립성 및 동적 바인딩 설계

### 4.1 설계 원칙

1. **앱은 DSH 없이도 완전히 동작한다.** 부팅 → 타이머/카드/트레이 → 리스너 준비. DSH는 선택적 신호원이다.
2. **포트·경로·사용자명을 코드에 넣지 않는다.** 모든 위치는 환경변수/표준 폴더/패키지 상대경로에서 해석한다.
3. **브라우저는 앱의 존재를 직접 알 필요가 없다.** same-origin host 라우트가 유일한 창구다.
4. **알림 실패가 DSH 턴을 방해하지 않는다.** 승인/질문 waterfall은 즉시 `next()`를 호출하고, 전송은 백그라운드로 보낸다.
5. **중복 알림은 구조적으로 막는다.** 탭 리더 + 앱 이벤트 id 멱등성.
6. **오디오는 검증된 경로(브라우저)가 소유한다.** 앱은 시각 알림을 소유한다.

### 4.2 컴포넌트 아키텍처

```
┌─────────────────────────────────────────────────────────────────────┐
│ DSH Web (origin = http://127.0.0.1:<가변포트>)                        │
│                                                                     │
│  ┌──────────────────────────────┐      ┌──────────────────────────┐  │
│  │ client half (browser)        │      │ host half (Node)         │  │
│  │ • remote.$on 이벤트 구독      │      │ • /api/local/dsh-notify/*│  │
│  │ • 루트 세션 필터/쿨다운       │─────▶│ • 앱 디스크립터 탐색      │  │
│  │ • 탭 리더(Web Locks)         │ POST │ • loopback HTTP 클라이언트│  │
│  │ • Web Notification/Web Audio │◀─────│ • 결과/상태 반환          │  │
│  │ • 인페이지 토스트/상태 배지   │      │ • 앱 config 읽기          │  │
│  └──────────────────────────────┘      └───────────┬──────────────┘  │
└─────────────────────────────────────────────────────┼─────────────────┘
                                                      │ 127.0.0.1:<ephemeral>
                                                      │ X-DSH-Notify-Token
┌─────────────────────────────────────────────────────▼─────────────────┐
│ DSH Notify resident app (PowerShell 7 / WPF)                          │
│  • single-instance mutex                                              │
│  • timer/provider/tray/card (기존)                                     │
│  • TcpListener loopback:0 + 최소 HTTP/1.1                              │
│  • runtime.json 원자적 기록 (port/token/pid/protocol)                  │
│  • 요청 검증 → UI 큐 → 팝업/트레이 상태                                │
│  • 로그 로테이션                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

### 4.3 컴포넌트 책임

| 컴포넌트 | 책임 | 하지 않는 일 |
|---|---|---|
| client half | DSH 이벤트 감지, 루트 필터, 쿨다운, 탭 리더, same-origin POST, 브라우저 폴백, 권한/오디오 UX | 파일 시스템 접근, 앱 포트 직접 탐색, 토큰 보관 |
| host half | 앱 디스크립터 읽기/검증, loopback HTTP 전송, same-origin 라우트, 앱 config 노출, 로그 | DSH 이벤트 직접 구독(기본), UI 렌더링 |
| app listener | 인증, JSON 검증, 멱등성, UI 큐, 팝업, 상태 카운터 | DSH 프로토콜 지식, 브라우저 제어 |
| app timer/tray | 피크 판정, 카드, 트레이, 설정 | DSH 이벤트 구독 |

**왜 host half가 필요한가(대안 기각 근거):**

- 브라우저는 `%LOCALAPPDATA%\DSH Notify\runtime.json`을 읽을 수 없다.
- 앱 포트를 브라우저에서 스캔하는 것은 Private Network Access/CORS/보안상 불가능에 가깝다.
- DSH가 HTTPS(리버스 프록시)면 HTTP loopback 직접 호출은 mixed content로 차단된다. host half는 서버 측이므로 무관하다.
- 토큰을 브라우저에 노출하지 않는다.
- host half가 앱 config를 읽어 마스터 스위치를 일관되게 적용할 수 있다.

### 4.4 DSH 이벤트 계약

| 이벤트 | 수신 위치 | 판정 | 알림 | 지연 금지 |
|---|---|---|---|---|
| `api-session/status` `(id, running)` | client half | `running=false`, 루트 세션, 5초 쿨다운 | 완료 | 해당 없음(emit) |
| `api-session/error` `(id, message)` | client half | 루트 여부 선택, 5초 쿨다운 | 오류 | 해당 없음(emit) |
| `approval/request` `(request, next)` | client half | 항상 | 승인 필요 | **즉시 `next()`** |
| `user-questions/request` `(request, next)` | client half | 항상 | 질문 대기 | **즉시 `next()`** |
| `agent/status` idle | host half(선택) | headless relay에서만 | 완료 | 해당 없음 |
| `agent/error` | host half(선택) | headless relay에서만 | 오류 | 해당 없음 |
| `agent/turn-stopping` | **사용 금지** | — | — | serial, 금지 |

**루트 세션 필터:**

```js
const row = ctx.sessions.list.getSnapshot().byId[sessionId]
if (row && (row.parentId || row.origin === 'subagent')) return false
return true // 행이 아직 없으면 알림을 잃지 않기 위해 허용
```

현재 브리지의 `agents.roots()` 객체 동일성 비교보다 단순하고, 브라우저에서 사용 가능한 공개 API다.

**승인/질문 처리:**

```js
ctx.remote.$on('approval/request', function (request, next) {
  // 전송은 await 하지 않는다. 승인 UI/턴을 지연시키지 않는다.
  void notify('approval', this, request)
  return next()
})
```

`notify`는 실패해도 예외를 밖으로 던지지 않는다. `next()`는 정확히 1회 호출한다.

### 4.5 플러그인 패키지 설계

권장 위치: `DSH Notify\plugin\` (앱과 같은 저장소, DSH 프로필에는 링크/설치).

```
plugin/
  package.json
  cordis.patch.yml
  lib/
    index.js        # host half
    client.js       # browser half (module-loader CJS factory)
  README.md
```

`package.json` 핵심:

```json
{
  "name": "@local/dsh-notify",
  "version": "0.1.0",
  "private": true,
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
    - id: dsh-notify
      name: '@local/dsh-notify'
      config:
        desktopEnabled: true
        browserFallback: true
        notifyOnComplete: true
        notifyOnApproval: true
        notifyOnQuestion: true
        notifyOnError: true
        completeCooldownMs: 5000
        requestTimeoutMs: 800
```

**host half 골격:**

```js
export const name = 'dsh-notify'
export const inject = ['connection']

export function apply(ctx, config = {}) {
  // ctx.connection.fetch.register({ path: '/api/local/dsh-notify/status', ... })
  // ctx.connection.fetch.register({ path: '/api/local/dsh-notify/event', ... })
  // ctx.effect(() => disposer, 'dsh-notify: routes')
}
```

**client half 골격:**

```js
window.__ModuleLoader__.load({
  id: '@local/dsh-notify',
  factory: (require) => {
    const exports = {}
    exports.inject = ['remote', 'sessions', 'slots', 'locale']
    exports.apply = (ctx) => {
      // ctx.effect(() => ctx.remote.$on('api-session/status', ...), '...')
      // ctx.effect(() => ctx.slots.register(...), '...')
    }
    return exports
  },
})
```

**주의:** `dsh.client.inject`는 "이 패키지가 어떤 패키지에 의존하는가"라는 정보성 목록이고, 실제 Cordis 서비스 주입은 `exports.inject`의 서비스 이름(`remote`, `sessions`, `slots`, `locale`)이다. 둘을 혼용하면 로드 순서/서비스 미존재 오류가 난다.

### 4.6 로컬 앱 프로토콜

**전송:** loopback HTTP/1.1, `Content-Type: application/json; charset=utf-8`, `Connection: close`. chunked는 받지 않는다. 요청 본문 최대 16 KiB, 헤더 최대 8 KiB, 읽기 타임아웃 2초.

**인증:** `X-DSH-Notify-Token: <256-bit random>` 상수 시간 비교. 토큰은 `runtime.json`에만 있고 브라우저에는 절대 전달하지 않는다.

**GET `/v1/health`**

```json
{
  "ok": true,
  "app": "dsh-notify",
  "instanceId": "4f1c…",
  "pid": 60332,
  "version": "0.6.0",
  "protocol": 1,
  "startedAt": "2026-10-23T03:30:00+09:00",
  "capabilities": { "popup": true, "toast": false, "audio": false },
  "notifications": true
}
```

**POST `/v1/notify`**

```json
{
  "v": 1,
  "id": "b1e2c3d4-…",
  "kind": "complete",
  "title": "DSH 작업 완료",
  "body": "세션 작업이 끝났습니다. 결과를 확인하세요.",
  "sessionId": "session-…",
  "sessionTitle": "하이브리드 설계",
  "dshOrigin": "http://127.0.0.1:3080",
  "dshRoot": "http://127.0.0.1:3080/",
  "pageVisible": true,
  "pageFocused": false,
  "createdAt": 1760000000000
}
```

응답:

```json
{
  "ok": true,
  "accepted": true,
  "displayed": true,
  "deduped": false,
  "audio": "browser",
  "notifications": true
}
```

| 상태 | 의미 | 클라이언트 행동 |
|---|---|---|
| 200 `displayed:true` | 앱이 표시를 인수 | 브라우저 폴백 표시 안 함. 오디오만 재생(설정 시) |
| 200 `displayed:false` | 앱이 알림 꺼짐/무음 설정 | 폴백하지 않음(사용자가 끈 것) |
| 409/`deduped:true` | 같은 id 중복 | 폴백하지 않음 |
| 401 | 토큰 불일치 | 디스크립터 재읽기 1회 → 실패 시 폴백 |
| 403 | Host/Origin 검증 실패 | 폴백, 로그 |
| 426 | 프로토콜 불일치 | 데스크톱 경로 비활성, 폴백 |
| 429 | 속도 제한 | 폴백하지 않음(앱 생존) |
| timeout/connection refused | 앱 없음/멈춤 | 폴백, 상태 degraded |

**보안 검증(서버 측):**

- `RemoteEndPoint.Address`가 loopback인지 확인.
- `Host` 헤더가 `127.0.0.1:<port>` 또는 `localhost:<port>`인지 확인(DNS rebinding 방지).
- `Origin`이 있으면 `http://127.0.0.1:<port>`/`http://localhost:<port>`와 일치하는지 확인. 없으면 허용(host-to-host).
- CORS 헤더를 보내지 않는다. 브라우저 직접 호출을 전제하지 않는다.
- JSON 스키마/문자열 길이/제어문자 검증. `title` 120자, `body` 500자, `sessionTitle` 80자로 절단.
- `dshRoot`는 `http:`/`https:`만 허용하고, loopback 또는 설정된 public host만 클릭 시 연다.

### 4.7 포트 가변성·충돌 방지·자동 탐색

**앱 바인딩:**

1. `Local\DSHNotify` 뮤텍스 획득. 이미 실행 중이면 종료.
2. 데이터 디렉터리 생성.
3. `TcpListener(IPAddress.Loopback, 0)` 바인딩 → OS가 빈 포트 할당.
4. 32바이트 난수 토큰 생성.
5. `runtime.json`을 temp→rename으로 원자적 기록.
6. accept 루프를 `Start-ThreadJob`에서 시작. 요청은 `ConcurrentQueue`로 UI 스레드에 전달.
7. UI는 100ms `DispatcherTimer`로 큐를 비우고 팝업 표시(기존 1초 tick과 별도).

`runtime.json`:

```json
{
  "v": 1,
  "app": "dsh-notify",
  "instanceId": "4f1c…",
  "pid": 60332,
  "port": 54321,
  "token": "…",
  "protocol": 1,
  "appVersion": "0.6.0",
  "startedAt": "2026-10-23T03:30:00+09:00",
  "url": "http://127.0.0.1:54321/"
}
```

**왜 `TcpListener`인가:** `HttpListener`는 포트 0을 지원하지 않아 "빈 포트 예약 → 닫기 → HttpListener 바인딩" 경쟁이 생긴다. `TcpListener`는 포트 0을 원자적으로 잡고, http.sys URL ACL도 필요 없다. 이 PC에서 `HttpListener`를 비관리자로 `127.0.0.1:<임의포트>`에 바인딩하고 요청 수신까지 되는 것은 실측했지만, 포트 결정의 원자성 때문에 최소 HTTP 파서를 가진 `TcpListener`를 권장한다. 프로토콜이 `GET /v1/health`, `POST /v1/notify` 두 개뿐이라 파서 부담이 작다.

**탐색 순서(host half):**

1. `DSH_NOTIFY_ENDPOINT` 환경변수(개발/테스트 전용; `DSH_NOTIFY_TOKEN` 동반).
2. `%LOCALAPPDATA%\DSH Notify\runtime.json` (또는 `DSH_NOTIFY_HOME`).
3. 레거시 고정 후보 `127.0.0.1:47600–47609` — **마이그레이션 1회만**, `/v1/health`의 `app:"dsh-notify"` 서명 확인.
4. 없음 → `unavailable`.

**캐시/무효화:**

- 성공한 endpoint는 30초 캐시.
- `ECONNREFUSED`/timeout/401이면 즉시 캐시 무효화 후 디스크립터 재읽기.
- 디스크립터가 없으면 다음 이벤트에서 재시도(2초 백오프).
- PID가 죽었거나 `instanceId`가 다르면 stale로 간주하고 무시(파일 삭제는 앱/설치자가 수행).

**충돌 시나리오:**

| 상황 | 동작 |
|---|---|
| 다른 프로세스가 후보 포트 점유 | ephemeral이라 애초에 충돌 없음. 레거시 후보는 health 서명 불일치 시 건너뜀 |
| 앱 2개 실행 | 뮤텍스로 두 번째 종료. 첫 번째만 디스크립터 소유 |
| 앱 비정상 종료 | stale `runtime.json` 남음 → PID/health 검증 실패 → 무시, 다음 이벤트에서 재탐색 |
| DSH 재시작(포트 변경) | 페이지 출처가 바뀜. host half는 같은 출처 라우트라 영향 없음. 앱에는 새 `dshOrigin`이 전달됨 |
| 앱 재시작(포트 변경) | 디스크립터 갱신. host half가 다음 요청에서 재읽기. 페이지 새로고침 불필요 |
| 여러 DSH 인스턴스 | 각 페이지가 자기 `origin`을 보냄. 앱은 `origin+id`로 멱등성 유지 |

### 4.8 경로 추상화

**원칙:** 코드 루트와 데이터 루트를 분리한다.

| 루트 | 결정 | 예 |
|---|---|---|
| 코드 | 설치된 앱 폴더/패키지 폴더 | `$PSScriptRoot`, `import.meta.url` 기준 |
| 데이터 | `%LOCALAPPDATA%\DSH Notify` | `[Environment]::GetFolderPath('LocalApplicationData')` |
| 설정 | `<데이터>\config.json` | 기존 파일 자동 이전 |
| 캐시 | `<데이터>\cache\` | 공휴일/지역/상태 |
| 로그 | `<데이터>\logs\` | `core.log`, `plugin.log` |
| 런타임 | `<데이터>\runtime.json` | 포트/토큰/PID |
| 개발 오버라이드 | `DSH_NOTIFY_HOME` | 테스트/ portable 모드 |

**해석 규칙:**

- PowerShell: `$env:LOCALAPPDATA` → `[Environment]::GetFolderPath('LocalApplicationData')` → `Join-Path $HOME '.dsh-notify'`.
- Node: `process.env.LOCALAPPDATA` → `path.join(os.homedir(), 'AppData', 'Local')` (Windows) / `XDG_STATE_HOME` (POSIX).
- 플러그인 패키지 루트: `fileURLToPath(new URL('..', import.meta.url))`. 단, **데이터는 절대 패키지 루트에 쓰지 않는다.**
- 설정에는 상대경로만 저장하고 데이터 루트 기준으로 resolve.
- 금지 패턴: `C:\Users\<name>`, `nolit`, `C:/Users`, `3080`, `47600`(레거시 상수 제외), `OneDrive`.
- 공백/한글 경로: 모든 spawn은 인자 배열, PowerShell은 `-File "..."` 인용, JSON은 UTF-8.

**마이그레이션:**

1. 새 데이터 디렉터리에 `config.json`이 없고 프로젝트 루트에 있으면 1회 복사.
2. `cache/region.json`, `cache/deepseek-peak/*.json`, `cache/notify-state.json`도 복사.
3. 기존 파일은 삭제하지 않고 `.legacy`로 남기거나 그대로 둔다.
4. `DSH_NOTIFY_HOME`이 설정되어 있으면 마이그레이션하지 않는다(테스트 격리).
5. 설치 스크립트가 시작 메뉴 바로가기를 새 데이터 루트와 무관하게 코드 경로로 갱신한다.

**현재 exe와의 관계:** `build-exe.ps1`은 이미 `%LOCALAPPDATA%\DSH Notify\runtime`에 코드를 푼다. 새 설계는 그 `runtime`을 **코드 전용**으로 두고, 데이터는 그 상위(`%LOCALAPPDATA%\DSH Notify`)에 둔다. exe 배포를 쓰지 않더라도 동일한 데이터 배치를 쓴다.

### 4.9 듀얼 브리지 폴백 라이프사이클

상태 머신:

```
appStarting ──▶ appReady ──▶ pluginConnected ──▶ desktopMode
                    │                │
                    │                ├─ heartbeat 2회 실패 ──▶ degraded ──▶ browserFallback
                    │                └─ app 종료/디스크립터 삭제 ──▶ browserFallback
                    └─ 리스너 실패 ──▶ timerOnly (트레이 경고, DSH 알림 없음)

browserFallback ──▶ 앱 재시작/health 성공 ──▶ pluginConnected
```

| 시점 | 앱 | DSH 플러그인 | 사용자 경험 |
|---|---|---|---|
| 부팅 | 타이머/카드/트레이 시작, 리스너 준비, 디스크립터 기록 | (DSH 미실행) | 카드/트레이만 |
| DSH 페이지 로드 | 그대로 | host half가 health 확인, client half가 리더 선출 | 상태 배지 "데스크톱 연결됨" |
| 이벤트 발생 | 팝업 표시, 200 응답 | same-origin POST, 응답 대기(최대 800ms) | 앱 팝업 + 브라우저 소리(설정 시) |
| 앱 미실행 | 없음 | health 실패 → 폴백 | Web Notification + 소리 + 인페이지 토스트 |
| 앱 종료(실행 중) | 디스크립터 삭제 | 다음 이벤트에서 연결 실패 → 폴백 | 자연스러운 전환, 오류 UI 없음 |
| 앱 재시작 | 새 포트/토큰으로 디스크립터 | 다음 이벤트에서 재탐색 → 데스크톱 복귀 | 페이지 새로고침 불필요 |
| 탭 닫음 | 그대로 | 리더 해제, 다른 탭이 승계 | 다른 탭이 알림 담당 |
| DSH 종료 | 그대로 | 플러그인 언로드 | 카드/트레이 유지 |

**하트비트:** client half가 15초마다 `/api/local/dsh-notify/status`를 호출(또는 host half가 캐시된 health 반환). 2회 연속 실패 시 `browserFallback`. 이벤트 때마다 health를 호출하지 않는다.

**타임아웃:** 앱 응답 800ms. 앱이 살아 있는데 느린 경우 폴백하면 중복 위험이 있으므로, 앱은 요청을 큐에 넣자마자 202/200을 반환하고 실제 팝업은 UI 스레드에서 그린다. 즉 **응답은 "인수"이지 "표시 완료"가 아니다.**

### 4.10 중복 억제·다중 탭·리더 선출

**문제:** DSH 페이지를 여러 탭에 열면 각 탭이 같은 `api-session/status`를 받아 알림을 중복 전송한다.

**해결:**

1. **Web Locks 리더:** `navigator.locks.request('dsh-notify-leader', {mode:'exclusive'}, ...)`를 획득한 탭만 전송/폴백을 담당. 탭이 닫히면 자동 해제, 다른 탭이 승계.
2. **폴백 리더:** Web Locks가 없는 브라우저는 `localStorage` 리스(10초 TTL, 3초 갱신)로 선출.
3. **이벤트 id:** `crypto.randomUUID()` (없으면 `sessionId-kind-timestamp-random`). 앱은 최근 256개/60초 TTL로 멱등성 유지.
4. **쿨다운:** 같은 세션의 완료는 5초. `running=true`를 받으면 쿨다운 상태를 리셋.
5. **앱 측 멱등성:** 같은 id 재수신 시 `deduped:true`로 응답하고 표시하지 않는다. 플러그인 재시도는 같은 id를 쓴다.

리더는 알림 전송만 담당한다. 각 탭의 인페이지 상태 배지는 자기 탭에서 갱신해도 된다.

### 4.11 오디오 소유권 — 중요한 설계 변경

요구사항은 "상주 앱 미실행 시 Web Audio로 폴백"이지만, 기존 실측에서 **앱이 실행 중일 때 앱 오디오가 울리지 않는다.** 그대로 구현하면 "데스크톱 모드 = 무음 팝업"이 되어 요구의 의도(알림을 인지)를 충족하지 못한다.

**권장:** `audioOwner` 설정으로 분리한다.

| 모드 | 동작 | 권장 |
|---|---|---|
| `browser` (기본) | 앱이 팝업을 표시해도 브라우저가 소리를 재생. 앱은 무음 | ✅ 이 PC에서 유일하게 검증된 경로 |
| `desktop` | 앱이 소리를 시도(현재 실패). 브라우저는 무음 | ❌ 기본값 금지 |
| `off` | 모두 무음 | 사용자 선택 |

- 브라우저 오디오는 **첫 사용자 제스처**에서 `AudioContext`를 생성/`resume()`하고, 짧은 2음 차임(예: 880Hz/1175Hz, 120ms)을 합성한다. 에셋/라이선스 불필요.
- 탭이 백그라운드여도 오디오는 재생될 수 있다. 단, 브라우저가 오디오를 suspend하면 무음이 될 수 있으므로 상태 배지에 "소리 꺼짐"을 표시하고 한 번의 클릭으로 재활성화한다.
- DSH 페이지가 없으면 앱은 무음이다. 이는 알려진 한계로 문서화한다(앱 오디오 경로가 검증되면 `desktop` 모드 추가).

### 4.12 보안 모델

| 위협 | 완화 |
|---|---|
| 다른 로컬 프로세스가 앱 API 호출 | 256-bit 토큰, `runtime.json` ACL(현재 사용자), loopback 바인딩 |
| DNS rebinding | `Host` 헤더가 loopback authority인지 검증, CORS 미제공 |
| 악성 웹페이지가 localhost 호출 | 브라우저에서 직접 호출 불가(토큰 없음). host half만 토큰 보유 |
| 악성 DSH 플러그인/페이지가 이벤트 위조 | DSH 인증 쿠키 + same-origin 라우트. 앱은 고정 문구/길이 제한만 표시 |
| 클릭 시 임의 URL 실행 | `dshRoot`를 `http/https` + loopback/허용 host로 제한. `file:`, `javascript:`, UNC 거부 |
| 로그에 민감정보 | 프롬프트/코드/토큰 미기록. 이벤트 종류·세션 id·길이만 |
| 같은 사용자 악성코드 | 방어 범위 밖(문서화). 토큰은 사용자 세션 경계 내 신뢰 |

`runtime.json`은 `%LOCALAPPDATA%`의 상속 ACL로 대체로 충분하지만, 가능하면 `Set-Acl`로 현재 사용자 + SYSTEM만 허용한다. 브라우저에는 토큰을 절대 내려보내지 않는다.

### 4.13 설정 스키마

**앱 `config.json`(하위 호환 유지):**

```json
{
  "displayMode": "always",
  "opacity": 0.6,
  "position": { "x": 40, "y": 40 },
  "notifyOnChange": true,
  "notifications": true,
  "oledProtection": false,
  "oledIntervalSeconds": 60,
  "pollSeconds": 60,
  "providers": { "deepseek-peak": { "enabled": true, "makeupAsPeak": true, "refreshHours": 240 } },
  "bridge": {
    "enabled": true,
    "popupSeconds": 6,
    "soundOwner": "browser",
    "suppressWhenFocused": true,
    "completeCooldownMs": 5000,
    "maxEventsPerMinute": 30
  }
}
```

**플러그인 `cordis.patch.yml` config:** 위 4.5 참조. 경로는 넣지 않는다.

**우선순위:** 앱 `notifications`(마스터) > 플러그인 종류별 on/off > 브라우저 권한. 앱이 꺼져 있으면 host half가 `notifications:false`를 읽어 폴백도 하지 않는다(사용자가 명시적으로 끈 것).

### 4.14 오류 처리·관측성

- 앱 리스너 실패는 앱을 죽이지 않는다. 트레이에 "DSH 연동 불가" 상태를 표시하고 타이머는 계속.
- 플러그인 전송 실패는 DSH 턴에 영향을 주지 않는다. `ctx.logger.warn` 1회 + 카운터.
- 앱 `/v1/health`에 `received/displayed/deduped/lastEventAt` 카운터를 포함해 상태 패널에서 확인.
- 로그: `%LOCALAPPDATA%\DSH Notify\logs\core.log`, `plugin.log`. 1MB × 3 로테이션.
- 프로토콜 버전 불일치(426)는 사용자에게 "DSH Notify 앱 업데이트 필요"로 표시하고 브라우저 폴백으로 계속 동작.

### 4.15 호환성·버전

- 플러그인 `engines.dsh`: `>=0.2.1-rc.2 <0.3.0`. DSH 업그레이드 시 이벤트 허용 목록/슬롯 API를 재검증.
- 프로토콜 `v:1`. 앱/플러그인 중 하나만 업데이트되어도 426으로 안전 강등.
- `dshOrigin`은 페이지가 계산하므로 DSH 포트 변경에 코드 수정이 필요 없다.
- 클라이언트 번들은 hand-written CJS factory로 시작하고, 복잡해지면 tsdown으로 전환.

### 4.16 기각한 대안

| 대안 | 기각 이유 |
|---|---|
| 현재 파일 큐 유지 | web 프로필 미지원, 1초 폴링 지연, 경로 결합, 브라우저 폴백 없음 |
| 브라우저가 앱에 직접 HTTP | 포트 탐색 불가, CORS/mixed content, 토큰 노출 |
| 호스트 half만으로 완결 | 브라우저 알림/오디오/포커스 UX 없음. 요구의 폴백 미충족 |
| 앱이 DSH 이벤트를 직접 구독 | 앱은 DSH 프로세스가 아니며 플러그인 API를 쓸 수 없음 |
| named pipe만 사용 | Windows 네이티브로는 좋지만, 디버깅/관측이 어렵고 요구가 포트 설계를 명시. HTTP를 1차, pipe를 후속 하드닝으로 |
| 고정 포트 47600 | 충돌·다중 사용자·재시작에 취약. 레거시 fallback으로만 |
| Windows 토스트를 정본으로 | 집중 지원에서 배너 억제, 표시 여부 불확실 |
| `agent/turn-stopping` 사용 | serial이라 턴 종료 지연 위험. web에는 `api-session/status`가 있음 |

---

## 5. 단계별 구현 로드맵

> 공수는 1인 기준 대략치이며, DSH API 변경/브라우저 권한 이슈에 따라 변동한다.

### Phase 0 — 기준선 고정·계약 (0.5일)

**산출물**
- 이 보고서 승인/수정.
- 프로토콜 v1 스키마(JSON Schema 또는 문서 표).
- 경로/포트 금지 패턴 검사 스크립트 초안(테스트에 추가).
- 기존 19+1 테스트 기준선 재확인.

**종료 조건**
- 현재 테스트 19/19, bridge, docs 48 유지.
- 프로토콜/설정 필드가 동결됨.

### Phase 1 — 앱 데이터 루트·리스너 (1–1.5일)

**산출물**
- `Get-NotifyDataRoot`/`Resolve-NotifyPath` (config.ps1 또는 신규 `paths.ps1`).
- `%LOCALAPPDATA%\DSH Notify` 마이그레이션.
- `runtime.json` 원자적 기록/삭제, 토큰 생성.
- `TcpListener` loopback:0 + 최소 HTTP(`/v1/health`, `/v1/notify`).
- UI 큐(100ms) → 기존 `Show-NotifyPopup`.
- 단위 테스트: 경로 해석, 디스크립터, 인증, 본문 제한, 잘못된 Host/Origin, 중복 id.

**종료 조건**
- 앱 단독 실행 → `runtime.json` 생성, `health` 200.
- 앱 종료 → 디스크립터 삭제.
- 설정/캐시가 `%LOCALAPPDATA%`로 이전되고 기존 테스트 통과.
- 포트 0 바인딩이 10회 반복해도 충돌 없음.

### Phase 2 — 플러그인 host half (1–1.5일)

**산출물**
- `plugin/package.json`, `cordis.patch.yml`, `lib/index.js`.
- 디스크립터 탐색/캐시/무효화, health, `/v1/notify` 클라이언트.
- same-origin 라우트 `/api/local/dsh-notify/status`, `/event`.
- 앱 config 읽기(`notifications`), 로그, 카운터.
- Node 단위 테스트(임시 앱 서버 + 임시 `DSH_NOTIFY_HOME`).

**종료 조건**
- DSH 페이지 없이도 `curl`/Node로 라우트 호출 → 앱 팝업.
- 앱 미실행 시 `{delivered:false}` 응답, 예외 없음.
- 앱 재시작 후 다음 호출에서 자동 복구.

### Phase 3 — 플러그인 client half (2–3일)

**산출물**
- `lib/client.js` (module-loader CJS).
- `ctx.remote.$on` 4종, 루트 필터, 쿨다운, 이벤트 id.
- Web Locks 리더 + localStorage 폴백.
- same-origin POST, 800ms 타임아웃, 응답별 분기.
- Web Notification, Web Audio 차임, 인페이지 토스트, 권한/소리 활성화 배너.
- 상태 배지(`sidebar.footer.action`)와 "테스트 알림" 버튼.
- 브라우저 단위 테스트(모의 `ctx.remote`, `Notification`, `AudioContext`) + 수동 E2E.

**종료 조건**
- 앱 on: 팝업 1회, 브라우저 알림 없음, 소리 1회.
- 앱 off: Web Notification 1회 + 소리 1회(권한 후), 인페이지 토스트.
- 탭 2개: 알림 1회.
- 승인/질문: 알림 + `next()` 지연 < 50ms.

### Phase 4 — 설치·마이그레이션·문서 (1–2일)

**산출물**
- `install-plugin.ps1`: web 프로필에 junction/link, `dsh.profile.bundles`에 `@local/dsh-notify` 추가, `cordis.patch.yml` 검증.
- `install-shortcut.ps1` 갱신(데이터 루트와 무관, 코드 경로만).
- 기존 `config.json`/캐시 마이그레이션.
- 레거시 `bridge`는 desktop에 남기되, web에는 새 플러그인만.
- README/BOOT-CARD/설계 문서 갱신, `docs-contract` 통과.
- 롤백 절차 문서화.

**종료 조건**
- 새 사용자 홈(가짜 `LOCALAPPDATA`)에서 설치 → 앱/플러그인 동작.
- 공백/한글 경로에서 동작.
- DSH 포트 3080→3099 변경 후 페이지 새로고침만으로 동작(권한 재승인 UX 포함).
- `git status` clean, 테스트 전부 통과.

### Phase 5 — 하드닝 (1–2일)

**산출물**
- 보안 테스트: 토큰 오류, Host/Origin 위조, 16KB 초과, 429, stale descriptor.
- 장애 주입: 앱 kill/restart, DSH restart, 탭 수십 개, 네트워크 차단.
- 로그 로테이션, 상태 카운터, 진단 문서.
- 선택: headless relay(브라우저 없이 앱 알림), named pipe fallback, 코드 서명/SAC.

**종료 조건**
- 수용 매트릭스(§6) 전부 통과.
- 24시간 상주 스모크에서 메모리/포트 누수 없음.

**총 예상:** 6–10 작업일. 핵심 경로(Phase 1–3)는 4–6일.

---

## 6. 수용 기준 매트릭스

| ID | 시나리오 | 기대 | 검증 방법 |
|---|---|---|---|
| A1 | 앱 단독 부팅 | 카드/트레이/타이머, `runtime.json` 생성, DSH 없이 정상 | 수동 + `health` |
| A2 | DSH 포트 3080/3099/8080 | 코드/설정 수정 없이 알림 | 페이지 새로고침 후 이벤트 |
| A3 | 앱 미실행 + DSH 이벤트 | Web Notification + 소리 + 인페이지 토스트 | 앱 종료 후 이벤트 |
| A4 | 앱 실행 + DSH 이벤트 | 팝업 1회, 브라우저 알림 0회, 소리 1회 | 로그/화면 |
| A5 | 앱 실행 중 kill | 다음 이벤트부터 폴백, 오류 UI 없음 | kill 후 이벤트 |
| A6 | 앱 재시작 | 다음 이벤트부터 데스크톱 복귀, 페이지 새로고침 불필요 | 재시작 후 이벤트 |
| A7 | 탭 2개 | 알림 1회 | 두 탭 열고 이벤트 |
| A8 | 승인/질문 | 알림 + 승인 UI 정상, `next()` 지연 <50ms | 이벤트 계측 |
| A9 | 서브에이전트 완료 | 완료 알림 없음, 승인/질문은 알림 | 서브에이전트 실행 |
| A10 | 5초 내 중복 완료 | 1회만 | 연속 이벤트 |
| A11 | 공백/한글 경로 | 정상 | `DSH_NOTIFY_HOME` 임시 경로 |
| A12 | 다른 사용자명 | 정상 | `LOCALAPPDATA` 오버라이드 |
| A13 | 잘못된 토큰 | 401, 폴백 | curl |
| A14 | Host/Origin 위조 | 403, 폴백 | curl |
| A15 | 16KB 초과 body | 413/400, 앱 생존 | curl |
| A16 | stale runtime.json | 무시하고 재탐색 | 가짜 PID/포트 |
| A17 | DSH 재시작 | 페이지 새로고침 후 정상 | 재시작 |
| A18 | 기존 테스트 | 19/19 + bridge + docs | `tests\run-all.ps1` |
| A19 | 로그 로테이션 | 1MB×3 유지 | 로그 생성 |
| A20 | 24시간 상주 | 누수/포트 고갈 없음 | 스모크 |

---

## 7. 위험 등록부

| 위험 | 확률 | 영향 | 완화 |
|---|---|---|---|
| DSH 클라이언트 API 변경(0.2.x→0.3) | 중 | 높음 | `engines.dsh` 고정, 이벤트 허용 목록 테스트, 426 강등 |
| 브라우저 알림 권한 거부/포트 변경 | 높음 | 중 | 인페이지 활성화 배너, 권한 상태 표시, 인페이지 토스트 폴백 |
| 오디오 자동재생 차단 | 높음 | 중 | 첫 제스처에서 AudioContext unlock, 상태 배지, 무음 허용 |
| 앱 리스너와 WPF 스레드 충돌 | 중 | 높음 | ThreadJob + ConcurrentQueue + DispatcherTimer, UI 직접 조작 금지 |
| PowerShell HTTP 파서 버그 | 중 | 중 | 두 엔드포인트만, Content-Length/close, 16KB 제한, fuzz 테스트 |
| 방화벽/백신이 loopback 리스너 차단 | 낮음 | 중 | loopback only, 서명/예외 안내, health 진단 |
| SAC/서명 정책 | 높음(현 PC) | 중 | exe 비의존, 스크립트/바로가기 |
| 다중 탭 중복 | 높음 | 중 | Web Locks 리더 + 앱 id 멱등성 |
| 앱/플러그인 버전 불일치 | 중 | 중 | protocol v1, 426, 상태 패널 |
| 경로 마이그레이션 데이터 손실 | 낮음 | 높음 | 복사 후 원본 유지, `.legacy` 백업, 테스트 |
| 원격 DSH 호스트 | 중 | 중 | 동일 PC 가정 명시, 원격은 브라우저 폴백만 |
| 로그/캐시 무한 증가 | 중 | 낮음 | 로테이션, TTL |
| DSH HMR 미동작 | 중 | 낮음 | 수동 새로고침/재시작 문서화, hand-written bundle |

---

## 8. 미결 결정(권장 기본값)

| # | 결정 | 권장 | 대안 |
|---|---|---|---|
| 1 | 오디오 소유자 | `browser` | `desktop`(현재 실패), `off` |
| 2 | 전송 계층 | loopback HTTP ephemeral | named pipe |
| 3 | 플러그인 구현 | hand-written `lib/client.js` | TS + tsdown |
| 4 | headless relay | v1 off | Phase 5 opt-in |
| 5 | 상태 UI | `sidebar.footer.action` 배지 + 패널 | 배지 없이 로그만 |
| 6 | 마스터 스위치 | 앱 `config.notifications` | 플러그인 config 단독 |
| 7 | 데이터 마이그레이션 | 자동 1회 복사 | 수동 |
| 8 | 레거시 포트 fallback | 1 릴리스만 | 즉시 제거 |
| 9 | web/desktop 동시 설치 | web 우선, desktop은 검증 후 제거 | 둘 다 유지 |
| 10 | 알림 본문 | 고정 문구 + 세션 제목 80자 | 프롬프트 요약(금지) |

---

## 9. 부록

### A. 발견/전송 의사코드(host half)

```js
async function resolveEndpoint() {
  if (process.env.DSH_NOTIFY_ENDPOINT) return parse(process.env.DSH_NOTIFY_ENDPOINT)
  const file = join(dataRoot(), 'runtime.json')
  const info = JSON.parse(await readFile(file, 'utf8'))
  if (!alive(info.pid)) throw new Error('stale')
  return { url: `http://127.0.0.1:${info.port}`, token: info.token, instanceId: info.instanceId }
}

async function deliver(event) {
  const ep = await resolveEndpoint()
  const res = await fetch(`${ep.url}/v1/notify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-dsh-notify-token': ep.token },
    body: JSON.stringify(event),
    signal: AbortSignal.timeout(800),
  })
  return res.json()
}
```

### B. 브라우저 폴백 의사코드(client half)

```js
async function onEvent(kind, payload) {
  if (!leader()) return
  const result = await postSameOrigin('/api/local/dsh-notify/event', payload)
  if (result.delivered) {
    if (soundEnabled) playChime()
    return
  }
  if (result.reason === 'disabled' || result.reason === 'rate-limited') return
  showBrowserNotification(payload)
  if (soundEnabled) playChime()
  showInPageToast(payload)
}
```

### C. 데이터 배치

```
%LOCALAPPDATA%\DSH Notify\
  config.json
  runtime.json
  cache\
    deepseek-peak\2026.json
    region.json
    notify-state.json
  logs\
    core.log
    plugin.log
  runtime\            # exe 배포 시 코드 전용(선택)
```

### D. 검증 명령

```powershell
pwsh -NoProfile -File tests\run-all.ps1
node .\bridge\test.mjs
pwsh -NoProfile -File tests\docs-contract.ps1
```

### E. 실측 명령 요약

- `git status --short --branch`, `git log -5`
- `node -v`, `npm -v`, `pnpm -v`, `$PSVersionTable`
- `Get-CimInstance Win32_Process`로 `dsh web --port 3080`, `core.ps1` 확인
- `Get-NetTCPConnection -State Listen`로 3080 확인
- `Test-Path "$env:LOCALAPPDATA\DSH Notify"` → False
- `Select-String`로 `DEFAULT_ROOT`, `nolit`, `C:\Users` 검사
- `HttpListener`를 `127.0.0.1:<임의포트>`에 비관리자로 바인딩하고 요청 수신 확인
- DSH 설치본에서 `dsh.client`, `ctx.remote.$on` 허용 목록, `ctx.connection.fetch.register` 타입 확인

---

**다음 단계 제안:** 이 보고서의 §8 결정(특히 오디오 소유자·전송 계층·설치 프로필)을 승인하면 Phase 1(앱 데이터 루트/리스너)부터 착수한다. Phase 1은 DSH를 전혀 건드리지 않으므로, 기존 앱 동작을 유지한 채 가장 안전하게 검증할 수 있다.
