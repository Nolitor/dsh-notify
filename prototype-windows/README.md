# DSH Notify

> 상태: active · 최종 갱신: 2026-10-23 · git: main @ milestone-3 · 상위: [docs/WORK-PROTOCOL.md](docs/WORK-PROTOCOL.md)

DeepSeek Harness 작업 중 필요한 외부 상태를 Windows 트레이와 반투명 창으로 상시 보여주는 로컬 알림 플랫폼.

## 인덱스

| § | 섹션 | 이동 | 한 줄 요약 |
|---|---|---|---|
| 1 | 왜 필요한가 | [§1](#왜-필요한가) | 피크 2배 요금, 주간 79%가 오프피크 |
| 2 | 상태 | [§2](#상태) | 구현 진행 상태 |
| 3 | 문서 | [§3](#문서) | BOOT-CARD → 설계 → 스펙 순서 |
| 4 | 구조 | [§4](#구조) | providers / ui / cache / tests |
| 5 | 공휴일 데이터 | [§5](#공휴일-데이터) | holiday-cn 소스와 검증 |
| 6 | 참고 | [§6](#참고) | 공식 링크 |
| 7 | 알려진 문제 | [docs/2026-10-20-final-status.md](docs/2026-10-20-final-status.md) | 소리·토스트·SAC 등 마감 시점 한계 |
| 8 | 브라우저 호환성 | [§8](#-브라우저-호환성-안내-browser-compatibility) | Chromium 검증, Firefox/Safari 제약 |

첫 기능은 **DeepSeek API 과금 구간 인디케이터**다. 피크 시간(100% 요금)에는 적색, 오프피크(50%)에는 녹색으로 표시하고, 구간이 바뀔 때 트레이 알림을 한 번 띄운다.

## 왜 필요한가

DeepSeek API는 피크 시간에 2배 요금을 매긴다. 그런데 주간 시간의 약 79%가 오프피크다. 이 사실을 모르면 비용이 큰 작업을 비싼 시간대에 시작하게 된다.

**한국 시간 기준**

| 구간 | 요금 |
|---|---|
| 평일 00:00–10:00 | 50% |
| 평일 10:00–13:00 | **100%** |
| 평일 13:00–15:00 | 50% |
| 평일 15:00–19:00 | **100%** |
| 평일 19:00–24:00 | 50% |
| 토·일, 중국 공휴일 | 50% |

## 상태

**상주 앱 구동 가능.** 카드·트레이·설정 저장과 함께 **BYO 폰트 드래그 앤 드롭**, **트레이의 부팅 시 자동 실행 토글**, **Zero-Flicker 무음 진입점**이 동작한다. 알림음은 이 PC에서 재생 경로가 확보되지 않아 **넣지 않았다**. 마감 시점의 전체 상태와 한계는 [최종 상태 문서](docs/2026-10-20-final-status.md)에 정리되어 있다.

| 항목 | 상태 |
|---|---|
| 설계 문서 | 완료 |
| 기능 스펙 | 완료 |
| 작업 규약 | 완료 ([WORK-PROTOCOL.md](docs/WORK-PROTOCOL.md)) |
| 판정 코어 | 완료 (`providers/deepseek-peak.ps1`) |
| UI·트레이·상주 프로세스 | 완료 (`core.ps1`, `ui/*`, `app/tray.ps1`) |
| BYO 폰트 | 완료 (`app/font-loader.ps1`, 창에 .ttf/.otf 드롭) |
| 자동 시작 | 완료 (트레이 `부팅 시 자동 실행`, wscript → launch.js) |
| 무음 실행 | 완료 (`launch.js` + `core.ps1` FreeConsole) |
| 포터블 패키지 | 완료 (`build\build-portable.ps1` → `dist\DSH-Notify-Portable`) |
| 단일 exe | 빌드 스크립트 있음 (`build\build-exe.ps1`) — 이 PC는 SAC 정책으로 실행 차단. 공개 패키지에서는 제외 |

실행:

```powershell
.\launch.js                                # wscript/JScript 무음 진입점 (권장, 콘솔 없음)
.\start.cmd                                # PowerShell 7 검사 + UIPI 가드 + 숨김 실행 (디버그 폴백)
pwsh -NoProfile -File start.ps1             # 콘솔 없이 백그라운드 상주
pwsh -Sta -File core.ps1                    # 콘솔에서 확인용
pwsh -Sta -File core.ps1 -RunSeconds 10     # 10초만 띄우고 종료(스모크)
```

포터블 패키지:

```powershell
pwsh -NoProfile -File build\build-portable.ps1
# dist\DSH-Notify-Portable\ + DSH-Notify-Portable-0.2.0.zip + SHA256SUMS.txt
```

## 단일 exe (선택)

```powershell
pwsh -NoProfile -File build\build-exe.ps1      # → DSH-Notify.exe (약 123KB)
```

스크립트·아이콘·폰트를 리소스에 넣고, 실행 시 `%LOCALAPPDATA%\DSH Notify\runtime` 에 풀어 숨김 `pwsh` 로 띄운다. PowerShell 7 이 필요하다.

**이 PC에서는 실행이 차단된다.** Smart App Control 이 켜져 있어 서명 없는 exe 를 막는다(`애플리케이션 제어 정책에서 이 파일을 차단`). 우회하려면 SAC를 끄거나 코드 서명 인증서가 필요하다 — 지금은 바로가기 방식이 실용적이다. exe 는 SAC가 꺼진 다른 PC나 서명 후 배포용으로 쓴다.

`launch.js`는 Windows Script Host의 **JScript** 엔진을 사용한다. 이 PC는 VBScript 엔진이 꺼져 있지만
JScript는 동작하므로 `wscript.exe`로 콘솔 없이 실행된다. `start.vbs`는 레거시 파일이며 사용하지 않는다.
`core.ps1`은 시작 직후 `FreeConsole()`으로 부모 콘솔에서 분리된다.

표시 옵션은 `config.json` 또는 트레이 우클릭 메뉴:

| 옵션 | 값 | 의미 |
|---|---|---|
| `displayMode` | `always` (기본) / `peakOnly` | `peakOnly` 는 피크일 때만 카드를 띄우고, 오프피크에는 트레이만 남긴다 |
| `opacity` | 0.2–1.0 (기본 0.6) | 카드 불투명도 |
| `notifyOnChange` | true/false | 구간 전환 시 윈도 토스트 1회 |
| `notifications` | true/false | 전체 알림 스위치. 트레이 `알림` 체크와 같은 값이며 DSH 완료/승인 팝업까지 함께 끈다 |
| `oledProtection` | true/false (기본 false) | OLED 번인 완화. 켜면 카드를 주기적으로 5px씩 움직인다 |
| `oledIntervalSeconds` | 5 이상 (기본 60) | OLED 이동 간격(초) |
| `fonts/custom/*.ttf` | BYO | 창에 드롭한 폰트. 없으면 Consolas/Segoe UI |
| 부팅 시 자동 실행 | 트레이 메뉴 | 사용자 Startup `.lnk` 생성/삭제. 레지스트리/UAC 없음 |

테스트: `pwsh -NoProfile -File tests\run-all.ps1`

## 문서

| 문서 | 내용 |
|---|---|
| [BOOT-CARD.md](docs/BOOT-CARD.md) | **새 작업창에서 여기부터** |
| [설계 문서](docs/2026-10-20-dsh-notify-design.md) | 플랫폼 구조, provider 계약, UI·설정·오류 처리 |
| [과금 구간 스펙](docs/deepseek-peak-spec.md) | 요금 규칙, 판정 함수, 테스트 표 |
| [글로벌 타임존 실측](docs/2026-10-23-timezone-global-report.md) | 서울·런던·뉴욕/DST, 중국 공휴일, 10일 캐시 |
| [웹 플러그인 마운트](docs/2026-10-23-web-plugin-mount.md) | 실제 web 프로필 등록, Settings 알림, 테스트 알림 |

## 구조

```
DSH Notify\
  launch.js    wscript/JScript 무음 진입점 (UIPI 자동 재실행)
  start.cmd    PowerShell 7 검사 + UIPI de-elevation + 숨김 실행 (폴백)
  core.ps1     상주 프로세스 (WPF, 시작 직후 FreeConsole)
  app\         font-loader.ps1, tray.ps1 (자동 실행 토글)
  providers\   알림 소스 (현재 deepseek-peak 하나)
  notify\      우하단 팝업·피크 경고 CLI (토스트는 수동 확인용)
  bridge\      DSH 이벤트 → 토스트 플러그인 (@local/dsh-notify-bridge)
  ui\          인디케이터 창 (icons\neutral-*.ico)
  build\       build-portable.ps1 (공개 패키지)
  dist\        포터블 패키지 산출물 (gitignore)
  tests\       판정·알림·폰트·자동 실행 단위 테스트
```

## 공휴일 데이터

[NateScarlet/holiday-cn](https://github.com/NateScarlet/holiday-cn) — 국무원 공고를 매일 자동 크롤링한다.
2026년 데이터는 국무원 원문과 대조해 검증했다. 2027년은 매년 11월 공고 후 자동으로 채워진다.

## 🌐 브라우저 호환성 안내 (Browser Compatibility)

### 공식 지원 및 검증 완료

- **Chromium 계열 브라우저**: Google Chrome, Microsoft Edge, Naver Whale, Brave 등
- OS 데스크톱 알림 배너, 고유 태그 기반 중복 드롭 방지, Web Audio 및 시스템 알림음 연동이 모두 정상 작동하도록 검증되었습니다.

### 미검증 및 플랫폼 제약 (Unverified / Browser Policy Limits)

- **Mozilla Firefox**: 브라우저 자체의 엄격한 자동 재생(Autoplay) 차단 정책으로 인해, 주소창 설정에서 '오디오 및 비디오 자동 재생 허용'을 수동으로 활성화하지 않으면 비동기 턴 완료 사운드가 무음 처리될 수 있습니다.
- **Apple Safari (macOS / iOS)**: 백그라운드 탭 동결(Tab Freeze) 및 사용자 제스처 기반 미디어 정책으로 인해 백그라운드 사운드 출력이 제한될 수 있습니다.
- Chromium 외 브라우저 환경은 동작을 보증하지 않으며, 안정적인 알림 수신을 위해 **Chromium 기반 브라우저 사용을 권장**합니다.

> **🔊 소리가 나지 않을 때 (최초 1회 브라우저 설정 및 오디오 엔진 갱신)**:
>
> 1. 브라우저 주소창 왼쪽의 **설정(조율기/자물쇠) 아이콘** 클릭 ➔ **'사이트 설정'**
> 2. **'소리'** 항목을 `자동(기본값)`에서 **'허용'**으로 변경
> 3. 단순 새로고침(`F5`)으로는 크롬 백그라운드 오디오 서비스가 갱신되지 않을 수 있으므로, **주소창에 `chrome://restart`를 입력하여 브라우저를 완전히 재시작**한 뒤 사용

## 참고

- [DeepSeek 공식 가격표](https://api-docs.deepseek.com/quick_start/pricing)
- [DeepSeek Harness](https://deepseek-harness.github.io/deepseek-harness/en/guide/quickstart)
- 타이머 폰트 **Digital-7** © Style-7 — 개인용 무료. 배포/상업 조건은 [digital-7-license.txt](ui/assets/digital-7-license.txt)
- DeepSeek 로고는 DeepSeek 상표. 로컬 트레이 표시 용도로만 사용한다
