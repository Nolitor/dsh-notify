# DSH Notify 2-패키지 배포·운영 전략 — 기술 검증 및 실행 계획

<!-- skeleton:
version: 1.0
kind: report
status: historical
updated: 2026-10-23
summary: Technical review of the two-package deployment and operations strategy for DSH Notify, with the resulting execution plan.
-->


> 상태: proposed · 최종 갱신: 2026-10-23 · git: main @ 8129b54 · 상위: [README.md](../README.md)

- 대상: ① DSH 웹 알림 플러그인(공개 배포 지향), ② 윈도우 오프피크 위젯(포터블 스크립트 배포)
- 전제: 두 패키지는 서로 통신하지 않는다. 앱-플러그인 IPC/HTTP 브리지는 폐기한다.
- 이번 단계에서 **코드와 기존 파일은 수정하지 않았다.** 이 보고서만 추가했다.
- 실측 시점: 2026-10-23 03:40 KST (Asia/Seoul).
- **정책 변경(2026-10-23):** 모듈 A는 **PowerShell 7+ 필수**로 확정. 5.1 다운그레이드는 인코딩/IANA 시간대/스레드 호환 문제로 기각. [모듈 A PoC 보고서](2026-10-23-windows-widget-poc-report.md) 참조.

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 검증 결론 | 웹은 "사용 중 알림"으로 범위를 명시하면 Go, 위젯은 5.1 포팅·라이선스 정리 후 Go |
| 2 | 실측 근거 | SAC 켜짐, RemoteSigned, MOTW 차단/Bypass 통과, 5.1 WPF·Start-Job 동작 |
| 3 | 웹 플러그인 검증 | 탭 절전·알림/소리 억제·재연결·다중 탭 엣지 케이스 |
| 4 | 윈도우 위젯 검증 | ExecutionPolicy·SAC·MOTW·자동 시작·5.1 전환의 실제 변수 |
| 5 | 배포 아키텍처 | 모노레포 독립 패키지, npm + GitHub Releases |
| 6 | 최소 품 패키징 | 웹 패키지 체크리스트, 위젯 zip/실행/설치/제거 UX |
| 7 | 실행 로드맵 | Phase 0–4, 병목과 검증 절차 |
| 8 | 리스크·법무 | 폰트/로고/사운드 라이선스가 공개 배포의 최대 블로커 |
| 9 | 결정 필요 항목 | 5.1 vs 7, 배포 형태, 공개 범위 |
| 10 | 부록 | 실측 명령·결과, 릴리스 체크리스트 |

---

## 1. 검증 결론

| 항목 | 판정 | 근거/조건 |
|---|---|---|
| 웹 플러그인을 순수 브라우저 API로 격리 | **조건부 Go** | DSH 탭이 살아 있는 동안은 완결 가능. 탭이 닫히거나 discard되면 알림 없음. "always-on" 약속은 불가 |
| DSH 공식 Cordis 클라이언트 규격 준수 | **Go** | `dsh.client` + `lib/client.js` + no-op host + `cordis.patch.yml`로 구성 가능. 공식 마켓 등재는 별도 심사 |
| 윈도우 위젯을 비인증 포터블 스크립트로 배포 | **조건부 Go** | 기본 Windows 11에서 `powershell.exe -ExecutionPolicy Bypass`로 실행 가능. 단, 5.1 포팅과 라이선스 정리 필요 |
| Developer Mode 없이 동작 | **Go** | 스크립트 실행에 Developer Mode는 필요 없다. 필요한 것은 ExecutionPolicy 완화와 서명된 `powershell.exe`뿐 |
| 레지스트리/시스템 강제 설치 없이 운영 | **Go** | 사용자 Startup 폴더 `.lnk` + 앱 폴더 데이터. 관리자 권한/레지스트리 불필요 |
| 공개 오픈소스 배포 | **조건부 Go** | MIT LICENSE + BYO 정책 적용. Digital-7/DeepSeek 로고/`ding.wav`는 배포물에서 제외하고 사용자 주입만 허용 |
| 두 패키지의 완전 독립 배포 | **Go** | 공유 런타임 없음. 모노레포 독립 패키지 또는 별도 저장소 모두 가능 |

**핵심 판단:** 기술적 차단 요소는 크지 않다. 가장 큰 리스크는 ① 웹 플러그인의 "탭이 닫혀도 알림"을 기대하게 만드는 제품 약속, ② 윈도우 위젯의 PowerShell 5.1 호환성, ③ 폰트/로고/사운드 라이선스다. ③은 **BYO 정책 + MIT LICENSE**로 해소한다. 기본 패키지는 에셋을 배포하지 않고, 사용자 주입만 허용한다. 상세: [에셋·상표 라이선스 정책](2026-10-23-asset-policy.md).

---

## 2. 실측 근거

| 항목 | 실측값 | 의미 |
|---|---|---|
| OS | Windows 11 Home 10.0.26300, AMD64 | 대상 OS |
| PowerShell 7 | 7.6.7 | 현재 앱 실행 호스트 |
| Windows PowerShell | 5.1.26100.9711 | 기본 내장. 5.1 포팅의 베이스 |
| ExecutionPolicy | `LocalMachine: RemoteSigned`, 나머지 `Undefined` | MOTW 스크립트는 차단, Bypass는 통과 |
| Smart App Control | `VerifiedAndReputablePolicyState = 1` (켜짐) | 서명 없는 exe 차단. 스크립트는 별도 |
| Defender | RealTimeProtection `True`, TamperProtection `True` | 실행 시 실시간 검사 |
| MOTW + 5.1 기본 | `cannot be loaded ... is not digitally signed`, exit 1 | 다운로드 zip을 그대로 풀면 실행 차단 |
| MOTW + 5.1 Bypass | `PROBE_OK`, exit 0 | `-ExecutionPolicy Bypass`가 프로세스 범위에서 유효 |
| MOTW + `Unblock-File` | 차단 해제 후 기본 정책에서 `UNBLOCK_OK`, exit 0 | 대안: 1회 Unblock |
| 5.1 WPF/STA | `WPF_OK System.Windows.Window`, `FORMS_OK 2880` | WPF/Windows Forms가 5.1에서 로드됨 |
| 5.1 Start-Job | `JOB_OK` | `Start-ThreadJob` 대체 가능 |
| 5.1 미지원 | `Start-ThreadJob` 없음, `ConvertFrom-Json -AsHashtable` 없음 | 현재 코드의 PS7 의존 3곳 |
| WScript.Shell COM | 5.1/7 모두 `COM_OK` | `.lnk` 생성은 양쪽에서 가능 |
| 기존 바로가기 | Target이 Store `pwsh.exe` 경로 | 머신/버전 종속. 배포용으로 부적합 |

**PS7 의존 스캔 결과:** `core.ps1`의 `Start-ThreadJob`, `ConvertFrom-Json -AsHashtable`, `providers/deepseek-peak.ps1`의 `Start-ThreadJob` — 총 3곳. `??`, `?.`, `-Parallel` 등 다른 PS7 문법은 발견되지 않았다. **5.1 포팅 범위는 작다.**

---

## 3. 웹 플러그인 타당성 검증

### 3.1 순수 브라우저 API로 가능한 범위

가능:
- DSH 탭이 열려 있을 때 턴 완료/승인/질문/오류 알림.
- Web Notification, Web Audio, 인페이지 토스트, 상태 배지.
- 다중 탭 리더 선출, 세션 쿨다운, 권한/소리 상태 표시.

불가능:
- DSH 탭이 닫힌 뒤 알림.
- 브라우저가 탭을 discard/freeze한 동안 이벤트 수신.
- OS 집중 지원/방해 금지에서 알림이 실제 표시되는지 보장.
- 사용자가 브라우저/OS에서 알림을 끈 경우 이를 우회.

**따라서 제품 문구는 “DSH를 사용하는 동안의 알림”으로 한정해야 한다.** “항상 알림”이 필요하면 네이티브 앱/서비스 워커 푸시가 필요하며, 이는 현재의 2-패키지 독립 구조와 별개다.

### 3.2 엣지 케이스와 현실적 대응

| 엣지 케이스 | 발생 원인 | 영향 | 대응 |
|---|---|---|---|
| 탭 discard/freeze | Chrome Memory Saver, 절전 | 이벤트 수신 중단, 알림 누락 | `freeze`/`resume`, `visibilitychange`, `pageshow`에서 세션 목록 재동기화. 닫힌 탭은 수용 |
| 백그라운드 타이머 스로틀 | Chrome intensive throttling | 쿨다운/배지 갱신 지연 | 핵심 로직은 `setInterval`이 아니라 이벤트+타임스탬프 기반. 주기 작업 최소화 |
| 알림 권한 출처 종속 | 포트/도메인 변경 | 권한 재요청 필요 | 로드 시 `Notification.permission` 확인, 배지/패널에서 명확히 안내. 자동 재프롬프트 금지 |
| `127.0.0.1` vs `localhost` | 다른 origin | 권한/오디오 상태 불일치 | DSH 접속 URL을 하나로 고정하도록 문서화. 상태 배지에 현재 origin 표시 |
| OS 집중 지원/방해 금지 | Windows 설정 | 알림 배너 숨김, 앱은 인지 불가 | 인페이지 토스트 + 소리 병행. “표시 보장 없음” 문서화 |
| 브라우저 사이트 알림 차단 | 사용자 설정 | `Notification` 무시 | `permission === 'denied'` 감지 → 토스트 폴백 |
| 오디오 자동재생 차단 | 사용자 제스처 없음 | 첫 알림 무음 | 패널의 “소리 켜기”/“테스트 알림” 클릭에서 `AudioContext.resume()` |
| 탭/시스템 음소거 | 사용자 설정 | 소리 없음 | 감지 불가. 배지에 “소리 잠김” 안내, 테스트 버튼 제공 |
| 백그라운드 오디오 정책 | 브라우저/OS | 소리 지연/무음 | 알림 자체는 유지. 소리는 best-effort로 명시 |
| 다중 탭 | 같은 페이지 2개 이상 | 중복 알림 | Web Locks 리더 + localStorage 폴백 + Notification `tag` |
| BFCache 복원 | 뒤로/앞으로 | 구독/연결 stale | `pageshow.persisted`에서 재초기화/세션 목록 refresh |
| DSH 재연결 | 서버 재시작/네트워크 | 일반 완료 이벤트 유실 | 재연결 시 세션 목록으로 running→idle 전이 재구성. 승인/질문은 pending waterfall 재생 + `callId` dedupe |
| 승인 waterfall 중복 | 재연결 replay | 같은 승인 알림 2회 | `request.callId`/id 기반 5초 dedupe |
| 서브에이전트 이벤트 | child 세션 | 원치 않는 완료 알림 | `parentId`/`origin === 'subagent'` 필터. 승인/질문은 기본 허용 |
| DSH 버전 변경 | 0.2.x → 0.3 | 이벤트/슬롯 API 변경 | `engines.dsh` 고정, 이벤트 4종 단위 테스트, 로드 실패를 플러그인 내부로 격리 |
| 클라이언트 로드 실패 | `lib/client.js` 누락/문법 오류 | 플러그인만 비활성 | 패키지 `files` 검증, `npm pack` 내용 테스트, DSH Plugins 페이지에서 오류 확인 |
| CSP/번들 제약 | DSH 페이지 정책 | 인라인 스크립트/스타일 차단 가능 | module-loader 번들 + 슬롯 컴포넌트 사용. `eval`/인라인 `<script>` 금지 |

### 3.3 Web Notification/Web Audio의 구조적 한계

- **서비스 워커 푸시 없이는 탭 종료 후 알림이 불가능하다.** DSH는 로컬 서버이고 푸시 백엔드가 없으므로, Web Push(VAPID) 도입은 별도 서버/키 관리가 필요하다. 현재 범위에서 제외한다.
- **알림 표시 여부는 브라우저/OS가 최종 결정한다.** `new Notification()`이 예외 없이 반환되어도 배너가 안 뜰 수 있다. 앱 쪽에서 “표시됨”을 확정할 수 없다.
- **소리는 “들린다”를 보장할 수 없다.** AudioContext 상태, 탭 음소거, 시스템 볼륨, 출력 장치 변경에 종속된다. 테스트 버튼과 상태 표시가 필요하다.
- **탭을 살리기 위해 무음 오디오를 계속 재생하는 것은 금지한다.** 배터리/UX/정책 위반 소지가 크다.

---

## 4. 윈도우 위젯 타당성 검증

### 4.1 “비인증 포터블 스크립트”는 기술적으로 가능한가

가능하다. 단, 다음 조건이 맞아야 한다.

1. **호스트는 서명된 `powershell.exe`** (`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`)를 쓴다. 서명 없는 것은 `.ps1`(데이터)이며, SAC는 PE 실행 파일을 주로 막는다. 이 PC(SAC 켜짐, Defender 실시간)에서 MOTW 스크립트도 `-ExecutionPolicy Bypass`로 실행됐다.
2. **ExecutionPolicy는 프로세스 범위에서만 완화**한다. `-ExecutionPolicy Bypass`는 레지스트리를 바꾸지 않는다. 단, MachinePolicy/UserPolicy가 `AllSigned`/`Restricted`이면 우회되지 않는다.
3. **MOTW를 처리**한다. 다운로드 zip을 풀면 `.ps1`에 Zone.Identifier가 붙는다. 기본 RemoteSigned에서 차단되므로 `-ExecutionPolicy Bypass`를 모든 진입점에 넣거나, 1회 `Unblock-File`을 제공한다.
4. **Developer Mode는 필요 없다.** Developer Mode는 앱 사이드로딩/개발자 기능이며, PowerShell 스크립트 실행과 무관하다. 사용자에게 끄라고 요구하지 않는다.

### 4.2 실행 정책·보안 변수

| 변수 | 실제 동작 | 대응 |
|---|---|---|
| 기본 RemoteSigned + MOTW | 서명 없는 `.ps1` 차단 (실측 exit 1) | `-ExecutionPolicy Bypass` 또는 `Unblock-File` |
| Bypass | 프로세스 범위에서 통과 (실측 exit 0) | 바로가기/`start.cmd` 인자에 포함 |
| `Unblock-File` | MOTW 제거 후 기본 정책 통과 (실측) | 설치 스크립트에서 선택 제공 |
| MachinePolicy/UserPolicy `AllSigned` | Bypass보다 우선 | `Get-ExecutionPolicy -List` 확인 후 명확한 오류/문서. 엔터프라이즈는 지원 범위 밖 |
| AppLocker/WDAC | 경로/게시자 기반 차단 가능 | 사용자 폴더 실행이 막힌 환경은 지원 불가로 명시 |
| SAC | 서명 없는 exe 차단. 스크립트는 이 PC에서 통과 | exe 배포 금지, 스크립트 유지. 추후 정책 변화 모니터 |
| Defender | 실시간 검사. 숨김/자동시작 패턴에 민감 | 난독화/EncodedCommand/다운로드 금지, 소스 공개, 오탐 신고 |
| SmartScreen | zip/`.cmd` 다운로드 시 경고 가능 | “추가 정보 → 실행” 안내, 체크섬 제공, 가능하면 서명 |
| VBScript 엔진 | 이 PC에서 꺼짐 | `start.vbs` 사용 금지. `.cmd`/`.lnk` 사용 |
| Store `pwsh` 경로 | 사용자/버전별 경로, 업데이트 시 변동 | 5.1 `powershell.exe` 고정 경로 사용 권장 |
| 자식 프로세스 | 부모와 별개로 정책 적용 | 모든 spawn에 Bypass를 명시하거나, spawn 자체를 제거 |

### 4.3 PowerShell 5.1 vs 7 — 권장안

**권장: 위젯은 Windows PowerShell 5.1을 기준으로 하고, 7은 선택적 가속/호환으로 둔다.**

근거:
- 5.1은 Windows 10/11에 기본 내장. 일반 사용자에게 추가 설치를 요구하지 않는다.
- WPF/STA, Windows Forms, `Start-Job`, `WScript.Shell` COM이 5.1에서 동작함을 실측했다.
- 현재 코드의 PS7 의존은 3곳뿐이다.
  - `Start-ThreadJob` → `Start-Job` 또는 runspace로 대체.
  - `ConvertFrom-Json -AsHashtable` → PSCustomObject→hashtable 변환 또는 `JavaScriptSerializer`.
  - `Start-Process pwsh` → `$PSHOME\powershell.exe` 또는 인프로세스 팝업으로 대체.
- `pwsh` 7을 요구하면 Store 설치/경로/업데이트 변수가 추가되고, 일반 사용자 마찰이 커진다.

비용:
- `Start-Job`은 프로세스 기반이라 `Start-ThreadJob`보다 느리다. 60초 poll/5초 초기 sync에는 충분하지만, 시작 지연을 측정해야 한다.
- 5.1의 `Set-Content -Encoding UTF8`은 BOM을 쓴다. JSON/로그를 다른 프로그램이 읽을 경우 BOM 없는 UTF-8로 쓰는 helper가 필요하다.
- `ConvertTo-Json`/`ConvertFrom-Json`의 깊이/이스케이프 차이를 테스트해야 한다.
- 5.1에서는 `Get-Content -Encoding UTF8`이 BOM을 요구하는 경로가 있으므로, 스크립트 자체는 UTF-8 BOM으로 유지한다.

**대안:** v1은 `pwsh` 7 필수로 두고, v1.1에서 5.1 지원. 이 경우 “PowerShell 7 설치”가 최소 품의 일부가 되어 일반 사용자 이탈 가능성이 높다. 권장하지 않는다.

### 4.4 포터블 실행·상주 변수

| 변수 | 문제 | 대응 |
|---|---|---|
| 콘솔 창 깜빡임 | `powershell.exe`는 콘솔 앱 | 일상 실행은 `.lnk`(`WindowStyle=7`, `-WindowStyle Hidden`). 최초 1회는 `start.cmd` 허용 |
| 바로가기 경로 | 앱 폴더 이동 시 깨짐 | `install-startup.cmd`가 현재 경로로 `.lnk` 재생성. 이동 후 재실행 안내 |
| 시작 프로그램 | 사용자별 Startup 폴더 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`에 `.lnk`. 레지스트리/작업 스케줄러 불필요 |
| 관리자 권한 | 설치/레지스트리 없음 | 요구하지 않음. 실패 시 사용자 폴더에서 재실행 |
| 단일 인스턴스 | 중복 실행 | 기존 `Local\DSHNotify` 뮤텍스 유지 |
| 앱 폴더 쓰기 권한 | Program Files/읽기 전용 | 기본은 사용자 폴더. 쓰기 불가 시 `%LOCALAPPDATA%\DSH Notify`로 데이터 폴백 |
| 데이터/설정 | 레지스트리 오염 | 앱 폴더 `data\` JSON. 제거 시 폴더 삭제로 끝 |
| 업그레이드 | 설정 유실 | `data\` 보존, 앱 코드만 교체. 버전 파일 기록 |
| 종료 | 백그라운드 잔존 | 트레이 종료 메뉴. 제거 스크립트가 프로세스 종료 후 파일 삭제 |
| 절전/재개 | 타이머 지연 | `DispatcherTimer`는 재개 후 계속. provider poll이 따라잡음. 필요 시 `SystemEvents.PowerModeChanged`에서 즉시 poll |
| Explorer 재시작 | 트레이 아이콘 소실 | `TaskbarCreated` 메시지 재등록(후속) |
| 다중 모니터/DPI | 카드 위치 이탈 | 기존 `Get-ClampedPosition` 유지. 100%/125%/150% 테스트 |
| 한글/공백 경로 | 인용 누락 | 모든 경로 `-LiteralPath`, `"..."`, `WorkingDirectory` 명시 |
| Defender 오탐 | 숨김+자동시작 | 소스 공개, 난독화 금지, README에 동작 설명, 오탐 신고, 선택적 코드 서명 |
| 코드 서명 | 비용/인증서 | v1 필수 아님. 서명 시 `.ps1` Authenticode + zip 배포. SAC는 스크립트에 영향 적음 |

### 4.5 “최소 품” 사용자 여정(권장)

```
1) GitHub Releases에서 dsh-notify-widget-v0.1.0-win-x64.zip 다운로드
2) 사용자 폴더에 압축 해제 (예: %LOCALAPPDATA%\Programs\DSH Notify)
3) install-startup.cmd 더블클릭
   - 필요 시 ExecutionPolicy Bypass로 앱 시작
   - Startup 폴더에 바로가기 생성
   - 트레이에 위젯 표시
4) 이후 로그인 시 자동 시작
5) 제거: uninstall-startup.cmd → 바로가기/프로세스 정리 → 폴더 삭제
```

- `start.cmd`: 앱만 실행(설치 없이 체험).
- `install-startup.cmd`: 바로가기 생성 + 앱 시작.
- `uninstall-startup.cmd`: 바로가기 제거 + 프로세스 종료.
- `README.txt`: “Developer Mode 불필요”, “관리자 권한 불필요”, “데이터는 폴더 안”, “문제 시 로그 위치”.
- `LICENSE`, `THIRD-PARTY-NOTICES.md`, `SHA256SUMS.txt` 포함.

---

## 5. 배포 아키텍처

### 5.1 저장소 전략

**권장: 모노레포 + 독립 패키지/독립 릴리스.**

```
dsh-notify/
  packages/
    web-plugin/            # npm 배포
      package.json
      cordis.patch.yml
      lib/index.js
      lib/client.js
      locale/{en,ko}.json
      market/index.json
      icon.svg
      README.md
      LICENSE
    windows-widget/        # GitHub Releases zip
      app/
      start.cmd
      install-startup.cmd
      uninstall-startup.cmd
      README.txt
      LICENSE
      THIRD-PARTY-NOTICES.md
  docs/
  .github/workflows/
```

- 공유 런타임 코드는 없다. 공유하는 것은 문서/CI/릴리스 규칙뿐이다.
- 태그는 독립: `web-v0.1.0`, `widget-v0.1.0`.
- 나중에 커뮤니티가 커지면 `web-plugin`만 별도 저장소로 분리 가능. 처음부터 2개 저장소를 두면 CI/이슈/문서 중복이 크다.
- npm 패키지 이름은 `@local`을 쓰지 않는다. 예: `@nolit/dsh-notify` 또는 unscoped `dsh-notify-web`. `private: true`를 제거한다.

### 5.2 웹 플러그인 배포 채널

| 채널 | 용도 | 요건 |
|---|---|---|
| npm | 주 배포 | `npm publish`, `files` 화이트리스트, `engines.dsh`, `README`, `LICENSE` |
| DSH Plugin Market | 발견/설치 | `market/index.json`(format 1), `icon.svg`, `locale`, 버전 동기화 |
| GitHub Release | 오프라인/검증 | npm tarball 또는 zip, SHA256, changelog |

**공개 패키지 체크리스트:**

- [ ] `private` 제거, `license` 명시(MIT/Apache-2.0)
- [ ] `dsh.manifestVersion: 1`, `dsh.bundle.patch`, `dsh.client.platform: 'web'`
- [ ] `main`, `exports['./client']`, `files`에 `lib/client.js` 포함
- [ ] `lib/index.js`는 no-op host (파일/포트/네트워크 없음)
- [ ] `engines.dsh` 범위 고정, `peerDependencies` cordis
- [ ] `market/index.json`의 `versions`/`engines` 동기화
- [ ] `locale/en.json`, `locale/ko.json`, `icon.svg`
- [ ] 절대경로/사용자명/포트 상수 없음
- [ ] `npm pack` 내용 검사(불필요한 파일/비밀 없음)
- [ ] 깨끗한 DSH 프로필에서 설치/활성/비활성/제거 테스트
- [ ] DSH 0.2.1-rc.2 및 최신 호환 버전에서 로드 테스트

**“공식 규격” 주의:** `dsh.client`/Cordis 규격 준수는 가능하지만, DSH 공식 마켓 등재는 별도 심사·정책에 달려 있다. “공식”이라는 표현은 마켓 등재 이후에 쓰는 것이 안전하다.

### 5.3 윈도우 위젯 배포 채널

| 채널 | 용도 | 요건 |
|---|---|---|
| GitHub Releases zip | 주 배포 | `dsh-notify-widget-vX.Y.Z-win-x64.zip`, SHA256, README |
| winget/scoop | 후속 | 초기에는 수동 zip이 마찰이 적다. 패키지 정의 유지비용 존재 |
| 코드 서명 | 선택 | 인증서 구매/갱신 필요. v1 필수 아님 |

**zip 내부:**

```
DSH Notify Widget/
  app/
    core.ps1
    config.ps1
    providers/
    ui/
    assets/            # 라이선스 정리된 폰트/아이콘만
  start.cmd
  install-startup.cmd
  uninstall-startup.cmd
  README.txt
  LICENSE
  THIRD-PARTY-NOTICES.md
  SHA256SUMS.txt
```

**제외:** `DSH-Notify.exe`, `build-exe.ps1`(선택 빌드), `start.vbs`, 개발용 테스트/캐시, 사용자 `config.json`.

### 5.4 릴리스·버전 규칙

- 웹 플러그인: semver. `0.1.0` → `0.2.0` 기능, `0.1.1` 수정. `engines.dsh`는 최소/최대 범위.
- 위젯: semver. 앱 UI/설정 변경은 minor, 버그 수정은 patch.
- 두 패키지는 서로의 버전을 참조하지 않는다. 문서에서 “함께 쓰면 좋다” 정도만 안내.
- 체인지로그: `CHANGELOG.md` 또는 GitHub Release notes.
- 아티팩트 체크섬: SHA256. zip과 npm tarball 모두.

---

## 6. 최소 품 패키징

### 6.1 웹 플러그인

- 설치: `dsh plugin --profile web add @nolit/dsh-notify` 또는 DSH Plugins 페이지.
- 활성화: bundle 선택. 실패 시 Plugins 페이지에 오류 표시.
- 업데이트: `dsh plugin ... add @nolit/dsh-notify@latest` 또는 페이지 Update.
- 제거: bundle 비활성/제거. `localStorage` 설정은 남으므로 “초기화” 버튼 제공.
- 요구 사항: DSH 0.2.1-rc.2+, Chrome/Edge 최신, HTTPS 또는 loopback.
- 권한: 첫 사용 시 패널에서 알림/소리 활성화. 자동 프롬프트 없음.

### 6.2 윈도우 위젯

- 요구 사항: Windows 10/11, PowerShell 5.1(내장), 관리자 권한 불필요.
- 실행: `start.cmd` 또는 `install-startup.cmd`.
- 자동 시작: 사용자 Startup `.lnk`만. 레지스트리/작업 스케줄러 없음.
- 데이터: `app\data\` (쓰기 불가 시 `%LOCALAPPDATA%\DSH Notify`).
- 제거: `uninstall-startup.cmd` → 폴더 삭제. 레지스트리 흔적 없음(최근 문서/MRU 제외).
- 업그레이드: 새 zip을 같은 폴더에 덮어쓰기. `data\` 보존.
- 문제 진단: `app\data\logs\core.log`, “정보” 패널에 PowerShell 버전/ExecutionPolicy 표시.

### 6.3 실행 스크립트 설계(개념)

`start.cmd`:

```bat
@echo off
setlocal
set "APP=%~dp0app"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
start "" "%PS%" -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File "%APP%\core.ps1"
```

`install-startup.cmd`:

```bat
@echo off
setlocal
call "%~dp0start.cmd"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\install-shortcut.ps1" -Startup
```

- `start.cmd`는 최초 1회 콘솔이 보일 수 있다. 일상 실행은 생성된 `.lnk`를 쓴다.
- `.lnk` Target은 `powershell.exe` 고정 경로, Arguments에 `-ExecutionPolicy Bypass -Sta -NoProfile -WindowStyle Hidden -File "..."`.
- `WindowStyle=7`(최소화) + `-WindowStyle Hidden`으로 콘솔 깜빡임 최소화.
- `install-shortcut.ps1`은 `WScript.Shell` COM으로 `.lnk` 생성(5.1/7 모두 동작 확인). 실패 시 `start.cmd`만으로도 사용 가능.
- 자식 프로세스를 만들 경우 반드시 `-ExecutionPolicy Bypass`와 `$PSHOME\powershell.exe`를 쓴다. 가능하면 자식 spawn을 제거하고 인프로세스 팝업으로 대체한다.

---

## 7. 실행 로드맵

### Phase 0 — 정책·라이선스·호환성 스파이크 (1–1.5일)

**목표:** 공개 배포 가능 여부를 먼저 확정한다.

- BYO 정책 반영: 기본 시스템 폰트/중립 아이콘/합성음, 배포물에서 Digital-7·DeepSeek 로고·`ding.wav` 제외.
- `LICENSE`(MIT) 추가 완료, 사용자 주입 에셋 면책 문구 확인.
- 5.1 포팅 스파이크: `Start-ThreadJob`→`Start-Job`, `-AsHashtable` 제거, `core.ps1` 1회 실행.
- 깨끗한 Windows 11 VM(관리자 아님, 기본 ExecutionPolicy, SAC on)에서 `start.cmd` 테스트.
- 웹 플러그인: 빈 DSH 프로필에서 `dsh.client` 로드/슬롯/이벤트 4종 스모크.

**종료 조건:** 라이선스 문제 해소, 5.1에서 앱 10초 스모크 통과, 웹 플러그인 이벤트 로그 확인.

### Phase 1 — 웹 플러그인 완성 (2–3.5일)

- 이벤트 구독/필터/쿨다운.
- Notification/Web Audio/권한/토스트/배지.
- Web Locks 리더, 재연결/가시성 복원.
- 단위 테스트 + 수동 E2E.
- npm 패키징/`npm pack` 검사.

**종료 조건:** 수용 기준 A1–A9 통과, 깨끗한 프로필 설치/제거 성공.

### Phase 2 — 위젯 5.1 포팅·포터블 패키징 (1.5–2.5일)

- 5.1 호환 코드(3곳) 수정.
- `start.cmd`/`install-startup.cmd`/`uninstall-startup.cmd`.
- Startup `.lnk`, 단일 인스턴스, 데이터 폴더.
- 5.1/7 양쪽 테스트, WPF/DPI/다중 모니터/한글 경로.
- `DSH-Notify.exe`/`start.vbs` 제거.

**종료 조건:** 관리자 권한 없이 설치/자동 시작/종료/제거, 재부팅 후 자동 시작.

### Phase 3 — 릴리스 엔지니어링 (1–1.5일)

- CI: Windows runner에서 5.1/7 테스트, `npm pack`, zip 생성, SHA256.
- `market/index.json`, `icon.svg`, `locale`, README/CHANGELOG.
- GitHub Release 초안, 설치 문서, 문제 해결 문서.
- `npm publish --dry-run` / 실제 publish.

**종료 조건:** 아티팩트 재현 가능, 체크섬 일치, 문서만 보고 설치 가능.

### Phase 4 — 클린 VM·브라우저 매트릭스 검증 (1–2일)

- Windows 11 clean, Windows 10, SAC on/off, Defender on.
- Chrome/Edge 최신, Firefox best-effort.
- DSH 포트 3080/3099/임의 포트, `localhost`/`127.0.0.1`.
- 권한 허용/거부/차단, 다중 탭, 절전/재개, BFCache.
- 오탐/차단 로그 수집.

**종료 조건:** 치명 결함 0, 알려진 한계 문서화, 릴리스 승인.

**총 6–9일.** Phase 0에서 라이선스/5.1이 막히면 일정이 늘어난다.

### 기술적 병목과 해결

| 병목 | 왜 | 해결 |
|---|---|---|
| 5.1 포팅 | `Start-ThreadJob`/`-AsHashtable`/spawn 정책 | 3곳 교체, 양쪽 호스트 테스트, `Start-Job` 지연 측정 |
| 탭 discard | 브라우저 정책, 서비스 워커 푸시 없음 | 범위를 “사용 중 알림”으로 한정, resume 시 세션 목록 재동기화 |
| 알림 권한/오디오 | 출처/제스처/OS 정책 | 배지/패널/테스트 버튼, 토스트 폴백 |
| DSH API 변경 | 0.2.x 초기 버전 | `engines.dsh` 고정, 이벤트 4종 테스트, 플러그인 격리 |
| Defender 오탐 | 숨김+자동시작 | 소스 공개, 난독화 금지, 오탐 신고, 선택적 서명 |
| 라이선스 | 폰트/로고/사운드 | 공개 전 교체가 가장 빠름 |
| 테스트 매트릭스 | OS/브라우저/DPI/권한 조합 | Phase 0에서 VM 템플릿, 자동화 가능한 것만 CI |

---

## 8. 리스크·법무

### 8.1 공개 배포 전 반드시 해결

| 자산 | 현재 상태 | 공개 배포 리스크 | 권장 |
|---|---|---|---|
| `ui/assets/digital-7.ttf` | `freeware for home using only`, freeware software use credit needed, commercial license $24.95 | 오픈소스 패키지 재배포 조건 불명확 | **배포물에서 제외**. 기본은 시스템 폰트, 사용자가 `fonts/digital-7.ttf`를 직접 주입할 때만 적용 |
| `ui/assets/deepseek-logo*.png`, `ui/icons/deepseek-*.ico` | README에 “DeepSeek 상표, 로컬 트레이만” | 상표 재배포/공식 앱 오인 | **배포물에서 제외**. 중립 시계 아이콘 기본, 사용자 `icons/custom.ico` 지원 |
| `notify/ding.wav` | 라이선스 파일 없음 | 재배포 권리 불명 | **배포물에서 제외**. 웹은 Web Audio 합성, 위젯은 시스템 기본음 |
| 루트 `LICENSE` | 없음 | 오픈소스 배포 불가 | **MIT LICENSE 추가 완료**. 사용자 주입 에셋 면책 명시 |
| `DSH-Notify.exe` | 서명 없음, SAC 차단 | 공개 배포 시 혼란 | 공개 zip에서 제외. 선택적 서명 빌드로 분리 |
| `start.vbs` | VBScript 엔진 꺼짐 | 동작 불가 | 공개 패키지에서 제외 |

### 8.2 기술·운영 리스크

| 리스크 | 확률 | 영향 | 완화 |
|---|---|---|---|
| 사용자가 “항상 알림”으로 오해 | 높음 | 신뢰 하락 | README/UI에 “DSH 탭이 열려 있을 때” 명시 |
| 알림 권한 거부 | 높음 | 알림 없음 | 배지/패널/토스트, 명확한 안내 |
| 오디오 무음 | 높음 | 인지 약함 | 테스트 버튼, 소리 상태, 토스트 |
| 5.1 포팅 회귀 | 중 | 앱 오동작 | 5.1/7 양쪽 테스트, Phase 0 스파이크 |
| ExecutionPolicy AllSigned | 중 | 실행 불가 | 사전 감지/문서, 엔터프라이즈 미지원 명시 |
| Defender 오탐 | 중 | 실행 차단 | 소스 공개, 서명, 오탐 신고 |
| DSH 마켓 심사 거절 | 중 | 배포 채널 제한 | npm/GitHub 우선, 마켓은 후속 |
| DSH API 변경 | 중 | 플러그인 깨짐 | 버전 고정/테스트/격리 |
| 다중 탭 중복 | 중 | 알림 피로 | Web Locks + tag + 쿨다운 |
| 라이선스 위반 | 낮음/높음 | 법적 문제 | Phase 0에서 교체 |

---

## 9. 결정 필요 항목

| # | 결정 | 권장 |
|---|---|---|
| 1 | 위젯 PowerShell 기준 | **5.1 기준 + 7 선택** |
| 2 | 웹 플러그인 배포 이름 | `@nolit/dsh-notify` (가능하면 scope) |
| 3 | 저장소 | **모노레포 독립 패키지**, 필요 시 분리 |
| 4 | 위젯 배포 형태 | **GitHub Releases zip** (exe 없음) |
| 5 | 자동 시작 | 사용자 Startup `.lnk`만 |
| 6 | 폰트/로고/사운드 | **BYO 정책 확정**: 기본 시스템/중립/합성, 배포물에서 제외 |
| 7 | 코드 서명 | v1 선택, 없이 출시 |
| 8 | 웹 알림 범위 | “DSH 사용 중”으로 명시 |
| 9 | 공식 마켓 | npm/GitHub 먼저, 마켓은 후속 |
| 10 | 5.1 포팅 시점 | Phase 0 (출시 전) |

---

## 10. 부록

### A. 실측 명령 요약

```powershell
Get-ExecutionPolicy -List
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' |
  Select-Object VerifiedAndReputablePolicyState
Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled,IsTamperProtected
```

MOTW/Bypass 검증(임시 파일):

```powershell
$tmp = Join-Path $env:TEMP 'probe.ps1'
Set-Content $tmp "Write-Output 'PROBE_OK'"
Set-Content $tmp -Stream Zone.Identifier "[ZoneTransfer]`r`nZoneId=3"
powershell.exe -NoProfile -File $tmp                      # 차단
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp  # 통과
```

5.1 호환성:

```powershell
powershell.exe -NoProfile -Sta -Command 'Add-Type -AssemblyName PresentationFramework; [System.Windows.Window]::new()'
powershell.exe -NoProfile -Command 'Start-Job { "JOB_OK" } | Receive-Job -Wait'
powershell.exe -NoProfile -Command '(Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) -eq $null'
```

### B. 공개 릴리스 체크리스트

**웹 플러그인**
- [ ] `private` 제거, LICENSE/README/CHANGELOG
- [ ] `dsh.client`, `lib/client.js`, `cordis.patch.yml`, `market/index.json`, `locale`, `icon.svg`
- [ ] `npm pack` 내용 검사, 절대경로/사용자명/포트 없음
- [ ] 깨끗한 DSH 프로필 설치/활성/비활성/제거
- [ ] 알림/소리/권한/다중 탭/재연결 E2E
- [ ] `engines.dsh` 호환성 확인

**위젯**
- [ ] 5.1/7 스모크, WPF/DPI/다중 모니터/한글 경로
- [ ] `start.cmd`/`install-startup.cmd`/`uninstall-startup.cmd`
- [ ] Startup `.lnk` 생성/제거, 관리자 권한 없음
- [ ] 데이터 폴더 쓰기/읽기 전용 폴백
- [ ] `DSH-Notify.exe`, `start.vbs` 제외
- [ ] LICENSE/THIRD-PARTY-NOTICES/SHA256
- [ ] Defender/SAC/ExecutionPolicy 시나리오 문서화

### C. 참고

- 웹 플러그인 단독 사양: [2026-10-23-web-notify-plugin-spec.md](2026-10-23-web-notify-plugin-spec.md)
- 기존 앱 구조: [README.md](../README.md)
- 사이드바 매니저 배포 선례: `C:\Users\nolit\Workspace\projects\dsh-workspace\dsh-sidebar-manager` (npm + `market/index.json` + `locale` + `icon.svg`)
