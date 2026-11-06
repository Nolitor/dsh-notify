# BOOT CARD — 새 작업창 진입 카드

<!-- skeleton:
version: 1.0
kind: boot
status: historical
updated: 2026-10-24
summary: The track-local boot card used when dsh-notify was its own workspace; superseded by workspace bootcards/.
-->


> 상태: final · 최종 갱신: 2026-10-20 · git: main @ milestone-3 · 상위: [WORK-PROTOCOL.md](WORK-PROTOCOL.md)

> 이 카드는 **새 작업창에서 가장 먼저 읽는 문서**다. 여기까지 읽었으면 바로 작업을 시작할 수 있다.

## 인덱스

| § | 섹션 | 이동 | 한 줄 요약 |
|---|---|---|---|
| 1 | 한 줄 정의 | [§1](#한-줄-정의) | 트레이·반투명 창 알림 플랫폼 |
| 2 | 작업 디렉터리 | [§2](#작업-디렉터리) | 이 프로젝트 경로 |
| 3 | 읽는 순서 | [§3](#읽는-순서) | 설계 → 스펙 → 카드 |
| 4 | 현재 상태 | [§4](#현재-상태) | 문서 완료, 판정 코어 구현 |
| 5 | 확정된 사실 | [§5](#확정된-사실-재조사-불필요) | 요금·공휴일·환경 실측 |
| 6 | 미결 사항 | [§6](#미결-사항--구현-중-결정) | 구현 중 결정할 것 |
| 7 | 첫 작업 지시 | [§7](#첫-작업-지시) | 테스트 먼저 |
| 8 | 구현 시 주의 | [§8](#구현-시-주의) | UTC 날짜·안전 강등 |
| 9 | 작업 규약 | [§9](#작업-규약--git-flag--헤더인덱스) | GIT FLAG 3지점, 헤더/인덱스 선행 |
| 10 | 다른 작업창과의 관계 | [§10](#참고--다른-작업창과의-관계) | 독립 프로젝트 |

---

## 한 줄 정의

`DSH Notify`는 DeepSeek Harness 작업 중 필요한 외부 상태를 Windows 트레이와 반투명 창으로 상시 보여주는 로컬 알림 플랫폼이다. 첫 기능은 **DeepSeek 과금 구간(피크 100% / 오프피크 50%) 인디케이터**다.

---

## 작업 디렉터리

```
C:\Users\nolit\Workspace\projects\DSH Notify
```

새 작업창의 작업 디렉터리를 위 경로로 지정한다.

---

## 읽는 순서

| 순서 | 문서 | 목적 |
|---|---|---|
| 1 | `docs\2026-10-20-dsh-notify-design.md` | 플랫폼 구조, provider 계약, UI·설정·오류 처리 |
| 2 | `docs\deepseek-peak-spec.md` | 첫 기능의 요금 규칙, 판정 함수, 테스트 표 |
| 3 | 이 카드 | 진입점 |

설계 문서를 읽지 않고 구현하면 provider 계약을 어기게 된다. 반드시 1 → 2 순서로 읽는다.

---

## 현재 상태

| 항목 | 상태 |
|---|---|
| 설계 문서 | 완료 |
| 기능 스펙 | 완료 |
| 폴더 구조 | 생성됨 (`providers`, `ui`, `notify`, `tests`, `docs`) |
| 작업 규약 | 완료 ([WORK-PROTOCOL.md](WORK-PROTOCOL.md)) |
| git | `main @ milestone-3` (태그 목록: `git tag --list 'milestone-*'`) |
| 판정 코어 | 완료 — `providers\deepseek-peak.ps1` |
| UI·상주 프로세스 | 완료 — `core.ps1`, `ui\presenter.ps1`, `ui\indicator.ps1`, `ui\tray.ps1` |
| 실행 | `install-shortcut.ps1` (시작 메뉴) 또는 `start.ps1` (자동 시작 등록은 안 함) |
| 단일 exe | `build\build-exe.ps1` — 이 PC는 Smart App Control 로 실행 차단 |
| DSH 완료 팝업 | 완료 — 브리지 → `cache\popup-request.json` → 코어 팝업 (소리 없음) |
| 마감 문서 | [2026-10-20-final-status.md](2026-10-20-final-status.md) — 알려진 문제 포함 |
| 미구현 | 자동 시작 토글, 추가 provider(세션/예약), 알림음 |

**상주 앱이 동작한다.** 새 작업은 `tests\run-all.ps1` 이 초록인 상태에서 시작하고,
UI 변경 시 `pwsh -Sta -File ui\render-indicator.ps1 -Severity alert -Out out.png` 로 먼저 눈으로 확인한다.

---

## 확정된 사실 (재조사 불필요)

### 요금 규칙

- 피크: UTC 01–04, 06–10, **월–금**
- 한국 시간: **평일 10–13, 15–19**
- 오프피크 = 피크의 0.5배
- 출처: [Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing) 직접 확인

### 공휴일 데이터

- 소스: [NateScarlet/holiday-cn](https://github.com/NateScarlet/holiday-cn)
- URL: `https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json`
- **2026.json 검증 완료** — `papers[]`가 국무원 원문(`content_7047091.htm`)을 가리키며, 직접 받은 공고와 완전 일치
- `isOffDay: false` = 대체근무일
- **2027.json 은 지금 비어 있음** — 국무원 공고(매년 11월) 전

### 기술 환경 (확인 완료)

- PowerShell **7.6.7**
- `System.Windows.Forms` 로드 성공
- `PresentationFramework` (WPF) 로드 성공
- `schtasks.exe` 존재

### 실측값

- 2026-10-20 01:12 KST → **오프피크** (UTC 2026-10-19 16시)

---

## 미결 사항 — 구현 중 결정

| 항목 | 선택지 | 메모 |
|---|---|---|
| 자동 시작 | `HKCU\...\Run` 등록할지 | 사용자에게 물어본다 |
| 대체근무일 | 피크로 볼지 | 설정 플래그 `treatMakeupAsPeak`, 기본 `true` |
| 공휴일 갱신 주기 | 10일 유지 → 운영 후 재판단 | `refreshHours: 240` (2026-10-20 결정). 재검토 지표: 갱신 실패 빈도, 연중 추가 공고 발생, 놓친 임시휴일로 인한 실제 혼선 |
| 공인 IP 지역 검사 | 한다 — 하루 1회, 표시용 | 노트북은 KST 로 고정된 채 해외에 있을 수 있어 기기 시간대만으로는 현지 시각을 모른다. 판정은 UTC 고정이라 영향 없음. `Get-PeakReferenceTimeZones` 가 두 시간대·불일치를 반환 (spec §4.4) |
| 향후 provider | 세션/작업/예약 중 우선순위 | 첫 기능 검증 후 |
| `C:\Users\nolit\deepseek-peak-dsh` | 삭제할지 보류할지 | DSH 플러그인 초안. 이 계획에서 미사용 |

---

## 첫 작업 지시

1. `docs\deepseek-peak-spec.md` §5 의 테스트 표를 연다
2. `tests\peak-decisions.ps1` 부터 작성한다 — **테스트 먼저**
3. `providers\deepseek-peak.ps1` 의 `Get-PeakDecision` 을 구현해 8개 케이스를 통과시킨다
4. 통과 후 공휴일 캐시 로더를 붙인다
5. 그다음 UI (`ui\indicator.ps1`, `ui\tray.ps1`)

**1~5 완료.** 판정·캐시·시간대·토스트·아이콘·카드·트레이·상주 루프까지 초록이다.
다음 후보: 자동 시작 토글, 추가 provider(세션 길이·예약), 클릭 시 GUI 열기(COM activator).

**테스트 없이 UI 부터 만들지 않는다.** 판정이 틀리면 UI가 아무리 예뻐도 쓸모없다.

---

## 구현 시 주의

- **공휴일 판정은 UTC 날짜 기준.** KST 날짜로 바꾸면 자정 부근에서 하루 어긋난다
- **정보 부족 시 안전 강등**: 캐시 → 주말 규칙 → 추정 표시. 조용히 틀리지 않는다
- **provider 실패는 격리**: 하나 죽어도 나머지는 계속
- **알림은 전환 시 1회만**: 같은 구간 내 반복 금지

---

## 작업 규약 — GIT FLAG · 헤더/인덱스

전문은 [WORK-PROTOCOL.md](WORK-PROTOCOL.md). 여기에는 요약만 둔다. 새 작업창은 이 두 규칙을 **작업 전에** 세운다.

### GIT FLAG — 세 지점

| 지점 | 할 일 |
|---|---|
| START | `git status --short --branch` 로 트리 확인 → `git log -1 --format='%h %s'` 기준 해시 확인. 더러우면 먼저 기준 커밋 |
| STEP | 한 단계의 테스트가 **초록이 된 직후** 커밋. 실패 상태 커밋 금지 |
| END | `git status` clean 확인 → HEAD 해시 사용자에게 보고 |

커밋 형식: `<type>(<scope>): <요약>` + 본문 `왜 / 검증 / 결과`. 마일스톤에는 `milestone-N` 태그.

### 헤더 + 스켈레톤 인덱스 선행

- **문서**: 제목 아래 `> 상태: active · 최종 갱신: 날짜 · git: main @ milestone-N · 상위: 링크` 한 줄, 이어서 `## 인덱스` 표
- **스크립트**: `<# .SYNOPSIS ... #>` 헤더 + `#region INDEX` (줄번호 대신 심볼명 · 목적 · 대응 테스트)
- 파일을 쓰기 전에 헤더와 뼈대 인덱스를 먼저 만들고 내용을 채운다
- 구조(섹션·심볼)를 바꾸면 **같은 커밋에서** 인덱스를 갱신한다
- 강제 수단: `tests\docs-contract.ps1`, 전체 실행 `tests\run-all.ps1`

---

## 참고 — 다른 작업창과의 관계

이 프로젝트는 원래 일반 작업창에서 계획했다. 그 창은 **DSH 설치·정리 작업용**으로 계속 쓴다. 이 프로젝트는 독립적이며 DSH 프로필을 건드리지 않는다.
