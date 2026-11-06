# DSH Notify — 설계 문서

<!-- skeleton:
version: 1.0
kind: design
status: historical
updated: 2026-10-20
summary: Original DSH Notify design: goal, scope, and the plugin shape chosen before implementation started.
-->


> 상태: active · 최종 갱신: 2026-10-20 · git: main @ milestone-1 · 상위: [BOOT-CARD.md](BOOT-CARD.md)

- 작성일: 2026-10-20
- 상태: 승인됨 (판정 코어 구현 완료, UI 미착수)
- 프로젝트 루트: `C:\Users\nolit\Workspace\projects\DSH Notify`
- 첫 기능: DeepSeek 과금 구간 인디케이터

## 인덱스

| § | 섹션 | 이동 | 한 줄 요약 |
|---|---|---|---|
| 1 | 목적 | [§1](#1-목적) | 왜 만드는가, 성공과 안티골 |
| 2 | 구조 | [§2](#2-구조) | 계층, provider 계약, severity, 갱신 주기 |
| 3 | UI | [§3](#3-ui) | 인디케이터 창, 트레이, 알림 |
| 4 | 설정 | [§4](#4-설정) | config.json 기본값 |
| 5 | 오류 처리 원칙 | [§5](#5-오류-처리-원칙) | 안전 강등 표 |
| 6 | 파일 구성 | [§6](#6-파일-구성) | 최종 디렉터리 배치 |
| 7 | 확장 방법 | [§7](#7-확장-방법-미래) | provider 추가 4단계 |
| 8 | 확인된 기술 사실 | [§8](#8-확인된-기술-사실) | 재확인 불필요 항목 |
| 9 | 미결 사항 | [§9](#9-미결-사항) | 구현 중 결정 |
| 10 | 하지 않는 것 | [§10](#10-하지-않는-것) | 범위 밖 명시 |

---

## 1. 목적

DSH(DeepSeek Harness) 작업 중에 알아야 하는 외부 상태가 여러 개 있다. 지금은 그때그때 사람이 확인해야 하고, 확인을 잊으면 비용이나 시간이 낭비된다.

`DSH Notify`는 그 상태들을 한 곳에서 상시 보여주는 **로컬 알림 플랫폼**이다.

### 왜 지금인가

DeepSeek API는 피크 시간에 2배, 그 외 시간에 1배의 요금을 매긴다(오프피크가 피크의 0.5배). 실측 기준 주간 시간의 약 79%가 오프피크인데, 그 사실을 모르면 비용이 큰 작업을 피크에 시작하게 된다. 이 하나만으로도 알림 인프라를 만들 값이 있다고 판단했다.

### 성공의 정의

- 작업을 시작하기 전에 과금 구간을 확인하는 습관이 생긴다.
- 알림 소스를 추가할 때 UI를 다시 만들지 않는다.

### 안티골: 이렇게 되면 실패다

- 인디케이터가 화면을 방해해서 꺼버리게 된다.
- 알림이 너무 잦아서 무시하게 된다.
- 판정이 틀려서 잘못된 구간을 알려준다.
- 프로세스가 죽어도 사용자가 알아채지 못한다.

---

## 2. 구조

### 2.1 계층

```
DSH Notify (단일 상주 프로세스)
│
├── core.ps1              provider 로딩, 상태 집계, 설정 관리, 단일 인스턴스 보장
│
├── providers/            알림 소스 (각각 독립)
│   ├── deepseek-peak.ps1       DeepSeek 과금 구간  ◀ 첫 기능
│   ├── (비어 있음)             세션 길이·토큰 소모
│   ├── (비어 있음)             백그라운드 작업 완료
│   └── (비어 있음)             예약 작업 도래
│
├── ui/
│   ├── indicator.ps1     반투명 인디케이터 창
│   └── tray.ps1          트레이 아이콘 + 풍선 알림
│
└── cache/                provider가 쓰는 캐시
```

### 2.2 Provider 계약

모든 provider 스크립트는 **하나의 함수**를 내보낸다.

```powershell
function Get-State {
    param(
        [datetime] $Now,        # 로컬 시각 (provider가 필요 시 내부에서 UTC 변환)
        [hashtable] $Config,    # config.json 의 providers.<id> 섹션
        [string] $CacheDir      # 캐시 디렉터리 절대 경로
    )

    return [pscustomobject]@{
        Id           = 'deepseek-peak'      # 고유 식별자
        Label        = 'DeepSeek 과금'      # 화면 표시명
        Severity     = 'warn'               # ok | warn | alert
        Headline     = 'PEAK · 100%'        # 1줄 요약
        Detail       = '→ 다음 구간까지 2h 14m'
        NextChangeAt = [datetime]           # 다음 상태 변화 시각 (없으면 $null)
        NotifyText   = '대량 작업은 50% 구간까지 미루는 것을 검토하세요.'
    }
}
```

### 2.3 Severity 체계

| severity | 창 색 | 트레이 아이콘 | 풍선 알림 |
|---|---|---|---|
| `ok` | 녹색 `#1E7B3C` | 녹색 | 없음 |
| `warn` | 주황 `#B26A00` | 주황 | 전환 시 1회 |
| `alert` | 적색 `#B3261E` | 적색 | 전환 시 1회 |

여러 provider가 동시에 활성이면 **가장 높은 severity**가 창 색을 결정한다. 나머지는 창을 클릭했을 때 목록으로 보인다.

**DeepSeek 첫 기능의 매핑**
- 피크(100%) → `alert` (적색)
- 오프피크(50%) → `ok` (녹색)
- 판정 불가(데이터 없음) → `ok` + detail에 "추정" 표시

### 2.4 갱신 주기

```
60초마다: 모든 provider의 Get-State 호출 → 상태 집계 → UI 반영
캐시 만료 시(기본 240시간 = 10일): 기존 캐시로 즉시 응답 + 백그라운드 갱신
  — 갱신은 스레드 작업 1개, 실패 시 1시간 쿨다운. 미공고 파일(papers: [])은 24시간 TTL
하루 1회: 접속 지역(공인 IP) 확인 — 표시용. 판정은 UTC 고정이라 영향 없음
```

요일 규칙(평일 UTC 01–04, 06–10)은 고정이므로 매번 계산하고, 변하는 것은 공휴일 데이터뿐이다.
중국 공휴일 달력은 연간 공고가 11월에 확정되고 연중 임시휴일이 드물게 추가되므로 10일 주기면
충분하다. 갱신은 타이머가 아니라 "만료 후 첫 호출"에서 시작되며, 폴링을 막지 않는다(lazy + async).

기기 시간대는 해외에서도 KST 로 남아 있을 수 있다(노트북은 모바일처럼 자동 변경을 기대하기 어렵다).
그래서 하루 1회 IP 로 접속 지역 시간대를 확인해 두고, 기기 시간대와 다르면 UI 가 두 시간대를 병기한다.
IP 는 VPN 으로 바뀔 수 있으므로 표시 힌트로만 쓰고 판정에는 쓰지 않는다(§4.4 in spec).

provider가 실패하면 그 provider만 건너뛰고 나머지는 계속 돈다. 전체가 죽지 않는다.

**시작 경량화**: 창은 즉시 `00:00:00` 자리 상태로 뜨고, 5초 뒤 백그라운드 스레드에서 공휴일·지역
동기화를 수행한다. 동기화가 끝나면 값이 채워지고, 이후 60초 폴링으로 이어진다.
시작·동기화·폴링 오류는 `cache\core.log` 에 남긴다(진단용, git 제외).

---

## 3. UI

### 3.1 인디케이터 창

| 항목 | 값 |
|---|---|
| 크기 | 210 × 92 px |
| 배경 | 짙은 무채색 `#121212`, 알파 0.6, 모서리 10px, 테두리 없음 |
| 최상위 | 예 |
| 작업표시줄 | 미표시 |
| 이동 | 창 전체 드래그 |
| 위치 저장 | `config.json` |

**표시 내용** — 강조는 하나만: digital-7 타이머. 모두 영어, 가운데 정렬.
```
┌──────────────────────────────┐
│     DeepSeek Peak (100%)      ← Pretendard 10, CI 블루 #4D6BFE, 중앙
│        02:14:30               ← digital-7 46px, 중앙
│                                 본문(HH:MM) 피크 #E5534B / 오프 #4ADE80
│                                 콜론·초(:SS)는 배경색 #2C2C2C (존재감 최소)
│     Local 18:00–21:00 (UTC-7) ← 기기/현지 불일치일 때만, 9px, 중앙
└──────────────────────────────┘
```

- 아이콘(점) 없음. 상태는 **제목 문구** + **타이머 색**으로 전달
- 제목: `DeepSeek Peak (100%)` / `DeepSeek Off-Peak (50% discount)`. 50%는 사용량이 아니라 **피크 대비 가격 할인율**임을 명시한다
- 타이머는 `HH:MM:SS`. 앞의 `HH:MM` 만 색을 주고 **콜론과 초**는 배경과 같은 회색으로 죽인다
- 시작 시 동기화(공휴일/지역)를 기다리지 않는다: 카드는 즉시 `00:00:00` 으로 뜨고, 5초 뒤 백그라운드 스레드에서 동기화해 값이 채워진다
- 타이머 글꼴: `ui\assets\digital-7.ttf` 임베드, `file://…digital-7.ttf#Digital-7` 로드(없으면 Consolas 폴백)
  - digital-7 은 개인용 무료 폰트. 라이선스 원문: `ui\assets\digital-7-license.txt`
- 제목·현지 줄은 **시스템 설치 Pretendard**(`C:\WINDOWS\FONTS\PRETENDARD-REGULAR.OTF`). 임베드 폰트는 타이머 하나뿐
  - `tests\font.ps1` F4 가 WPF 가 실제로 Pretendard 파일을 해석하는지 확인한다
- 레이아웃 Grid: 제목 Top, 타이머 Center, 현지 줄 Bottom — 타이머가 카드 정중앙
- 타이머는 1초마다 재계산하지만 표시는 분 단위, 서버 호출 없음

실제 렌더(2배 확대, 어두운 배경 합성):

*[이미지: PEAK 카드 — `previews/indicator-alert.png`, 이 저장소에 포함되지 않음]*
*[이미지: OFF-PEAK 카드 — `previews/indicator-ok.png`, 이 저장소에 포함되지 않음]*

- 표시 모델: `ui\presenter.ps1` (순수) / 카드: `ui\indicator.ps1`
- 창 없이 렌더 검증: `pwsh -Sta -File ui\render-indicator.ps1 -Severity alert -Out out.png`

**표시 모드** (`config.displayMode`)

| 값 | 동작 |
|---|---|
| `always` | 항상 표시, 색만 바뀜 (기본값) |
| `peakOnly` | `alert` 또는 `warn` 일 때만 창 표시 |

### 3.2 트레이

- `NotifyIcon` 상주, 아이콘 색도 severity에 맞춰 교체
- 아이콘 자산: `ui\assets\deepseek-logo-source.png`(워드마크 포함 원본)
  → `ui\prepare-logo.ps1`(연결요소로 심볼만 크롭 → `ui\assets\deepseek-logo.png` 222px 마스터)
  → `ui\build-icons.ps1` → `ui\icons\deepseek-{green,red,amber,gray}.ico`
  - 현재 아이콘은 **green(ok) / red(alert) 2종**. provider 가 내는 상태가 둘뿐이라 warn·unknown 자산은 만들지 않는다
    - `warn`(amber `#B26A00`)·`unknown`(gray `#6B7280`) 은 생산자가 생길 때 `ui\icons.ps1` 의 Colors 에 한 줄 추가 후 재생성
  - 16/20/24/32/48/256 멀티 사이즈 PNG-in-ICO. 테스트: `tests\icons.ps1`, `tests\logo-mask.ps1`
  - 워드마크가 섞인 원본에서 심볼만 잘라야 16px 에서 깨끗하다. 크롭은 알파 연결요소 최대값 기준
  - 원본 로고는 DeepSeek 상표다. 로컬 트레이 표시에만 쓰고 배포물에 재배포하지 않는다
- 우클릭 메뉴: `지금 갱신` / **`알림`(체크)** / **`OLED 보호`(체크)** / `항상 표시`(체크) / `피크일 때만`(체크) / `위치 초기화` / **`카드 보이기`(체크)** / `종료`
  - 체크 표시로 현재 상태를 바로 알 수 있다. `알림` 을 끄면 피크 전환 토스트와 DSH 완료/승인 팝업이 모두 멈춘다(config `notifications`)
  - `OLED 보호` 를 켜면 `oledIntervalSeconds`(기본 60초)마다 카드를 **5px 씩 네 방향으로 순환**시킨다(번인 완화). 저장되는 기준 위치는 그대로 두고 표시 오프셋만 움직인다
  - `카드 보이기` 체크는 실제 창 표시 상태(`IsVisible`)를 반영한다. 끄면 숨김, 켜면 표시
- 툴팁에 전체 provider 상태 요약

### 3.3 알림

- severity가 **바뀔 때만** 1회 풍선 알림
- 같은 severity가 유지되는 동안 재알림 없음
- 상태 파일(`cache/notify-state.json`)에 마지막 severity 기록

---

## 4. 설정

`config.json` (프로젝트 루트)

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
  "providers": {
    "deepseek-peak": {
      "enabled": true,
      "treatMakeupAsPeak": true,
      "refreshHours": 240
    }
  }
}
```

설정 파일이 없으면 기본값으로 생성한다. 잘못된 JSON이면 기본값으로 되돌리고 트레이 툴팁에 경고를 남긴다.

---

## 5. 오류 처리 원칙

핵심 원칙: **정보가 부족하면 안전한 쪽으로 강등하고, 강등 사실을 숨기지 않는다.**

| 상황 | 동작 |
|---|---|
| 네트워크 없음 | 캐시 사용 → 캐시도 없으면 주말 규칙만 |
| 공휴일 JSON 파싱 실패 | 해당 파일 무시, 캐시 사용, 주말 규칙 |
| 해당 연도 데이터 미공고 | `papers: []` 감지 → 주말 규칙, detail에 "공고 전" 표시 |
| provider 스크립트 오류 | 해당 provider만 제외, 나머지 계속 |
| 트레이 아이콘 생성 실패 | 창만으로 동작 계속 |
| 이미 실행 중 | 뮤텍스로 중복 차단, 기존 인스턴스에 신호 |
| config 손상 | 기본값 사용 + 경고 표시 |

---

## 6. 파일 구성

```
DSH Notify\
  docs\
    2026-10-20-dsh-notify-design.md     이 문서
    deepseek-peak-spec.md               첫 기능 상세
    BOOT-CARD.md                        새 창 진입 카드
  providers\
    deepseek-peak.ps1
    _template.ps1                       새 provider 작성용 빈 틀
  ui\
    indicator.ps1
    tray.ps1
  cache\                                런타임 생성 (git 제외)
  tests\
    peak-decisions.ps1                  판정 단위 테스트
  core.ps1
  config.json                           런타임 생성
  start.vbs                             콘솔 없이 실행
  README.md
```

---

## 7. 확장 방법 (미래)

새 provider를 추가하는 절차:

1. `providers/_template.ps1`를 복사해 이름 변경
2. `Get-State` 구현
3. `config.json`의 `providers.<id>`에 `enabled: true` 추가
4. UI는 손대지 않음

이 절차가 4단계를 넘으면 구조가 잘못된 것이므로 계획을 다시 세운다.

---

## 8. 확인된 기술 사실

조사 시점(2026-10-20) 기준 실제 확인한 것:

- PowerShell 7.6.7
- `System.Windows.Forms` 로드 성공
- `PresentationFramework` (WPF) 로드 성공
- `schtasks.exe` 존재
- 프로젝트 디렉터리는 원래 비어 있었음

이 사실들은 구현 시 전제로 삼는다. 재확인이 필요한 항목은 아니다.

---

## 9. 미결 사항

구현 단계에서 결정할 것:

| 항목 | 선택지 | 결정 시점 |
|---|---|---|
| 자동 시작 등록 | `HKCU\...\Run` 등록 여부 | 구현 후 사용자 확인 |
| 대체근무일 해석 | 피크로 볼지 오프피크로 볼지 | 설정 플래그로 양쪽 지원 |
| 향후 provider 우선순위 | 세션/작업/예약 중 무엇 먼저 | 첫 기능 검증 후 |
| DSH 플러그인 초안 처리 | `C:\Users\nolit\deepseek-peak-dsh` 삭제 여부 | 구현 후 |

---

## 10. 하지 않는 것

- **DSH 프로필 변경** — 이 플랫폼은 DSH 외부에서 독립 동작한다
- **하네스 실행 감지** — GUI 앱의 실행 시점을 외부에서 안정적으로 잡기 어렵다. 대신 구간 전환 알림으로 같은 목적을 달성한다
- **요금 조작** — 불가능하며 시도하지 않는다
- **클라우드 동기화** — 로컬 전용. 설정은 파일로 관리한다
