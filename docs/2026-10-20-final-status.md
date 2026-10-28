# DSH Notify — 최종 상태와 알려진 문제

> 상태: final · 최종 갱신: 2026-10-20 · git: main @ milestone-3 · 상위: [WORK-PROTOCOL.md](WORK-PROTOCOL.md)

이 문서는 "지금 이 버전을 그대로 두고 멈춘다"는 결정에 따라, 현재 동작·구조·한계를 한곳에 정리한 마감 문서다.

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 현재 버전 | 마지막 커밋·태그·실행 방법 |
| 2 | 동작하는 기능 | 카드·트레이·DSH 팝업·동기화 |
| 3 | 구조 | 파일 맵과 이벤트 경로 |
| 4 | 설정 | config.json 키 |
| 5 | **알려진 문제** | 반드시 읽을 것 — 소리/토스트/SAC |
| 6 | 진단 로그 | core.log·bridge.log·popup 로그 |
| 7 | 테스트 | 실행 명령과 현재 결과 |
| 8 | 다음 후보 (미착수) | 클라이언트 오디오 등 |

---

## 1. 현재 버전

| 항목 | 값 |
|---|---|
| 브랜치 | `main` |
| 태그 | `milestone-3` (문서·팝업 마감) |
| 실행 | 시작 메뉴 `DSH Notify` 바로가기 또는 `pwsh -NoProfile -File start.ps1` |
| 종료 | 트레이 고래 아이콘 우클릭 → `종료` |
| 요구 | PowerShell 7, Windows 10/11, DSH 프로필에 브리지 플러그인 등록됨 |

## 2. 동작하는 기능

- **피크/오프피크 카드**: 제목 `DeepSeek Peak (100%)` / `DeepSeek Off-Peak (50% discount)`. digital-7 타이머 `HH:MM:SS`, 초와 콜론은 배경색(`#2C2C2C`), 본문 색 피크 `#E5534B` / 오프피크 `#4ADE80`, 제목 CI 블루, 투명도 0.6
- **트레이 메뉴**: 지금 갱신 / 알림(체크) / OLED 보호(체크) / 항상 표시(체크) / 피크일 때만 / 위치 초기화 / 카드 보이기(체크) / 종료
- **OLED 보호**: 켜면 `oledIntervalSeconds`(기본 60초)마다 카드를 5px씩 네 방향 순환. 저장 기준 위치는 유지
- **시작 경량화**: 창은 즉시 `00:00:00` 으로 뜨고 5초 뒤 백그라운드 스레드에서 공휴일·지역 동기화
- **DSH 완료/승인 팝업**: 브리지가 `cache\popup-request.json` 을 남기면 코어가 팝업 표시 (소리 없음)
- **서브에이전트 완료 필터**: 완료 알림은 루트 세션만. 승인/질문은 서브에이전트 것도 알림
- **알림 전체 스위치**: 트레이 `알림` 체크 = `config.notifications`. 코어 전환 토스트와 DSH 팝업을 함께 끔

## 3. 구조

```
DSH host plugin  bridge\index.js (@local/dsh-notify-bridge)
   ├─ 턴 완료/승인/질문/오류 이벤트 구독 ({global:true})
   └─ cache\popup-request.json 기록
            ↓ (1초 tick 폴링)
core.ps1 (상주 WPF)  ── 카드·트레이·팝업
   ├─ providers\deepseek-peak.ps1  판정·공휴일 캐시
   ├─ ui\presenter.ps1             표시 모델
   ├─ ui\indicator.ps1             카드
   ├─ ui\tray.ps1                  트레이
   └─ ui\popup.ps1                 우하단 팝업
```

- 포트·웹서버·데몬 없음. 파일 큐 + 프로세스 내부 타이머만 사용
- DSH 프로필 등록: `~\.dsh\profiles\desktop\node_modules\@local\dsh-notify-bridge` junction + `cordis.patch.yml` 의 insert 엔트리 (백업 `cordis.patch.yml.bak`)
- 브리지는 로더 핫 리로드로 재시작 없이 반영된다. 적용 증거: `cache\bridge.log` 의 `bridge x.y.z applied: ...`

## 4. 설정

`config.json` (프로젝트 루트). 트레이 메뉴가 일부 값을 직접 바꾼다.

| 키 | 기본 | 의미 |
|---|---|---|
| `displayMode` | `always` | `peakOnly` 면 피크일 때만 카드 |
| `opacity` | 0.6 | 카드 불투명도 (0.2–1.0) |
| `position` | 저장값 | 카드 기준 위치 (OLED 오프셋 제외) |
| `notifyOnChange` | true | 구간 전환 시 토스트 1회 |
| `notifications` | true | 전체 알림 스위치 |
| `oledProtection` | false | OLED 번인 완화 이동 |
| `oledIntervalSeconds` | 60 | 이동 간격(최소 5초) |
| `pollSeconds` | 60 | provider 폴링 주기 |
| `providers.deepseek-peak` | enabled/treatMakeupAsPeak/refreshHours(240) | 공휴일·판정 옵션 |

## 5. 알려진 문제

| 심각도 | 문제 | 원인/현상 | 현재 대응 |
|---|---|---|---|
| **높음** | **DSH 팝업 소리 없음** | 이 PC에서 WinMM(`SoundPlayer`/`PlaySound`)은 스피커 앰프까지 도달하지 않고 "뽁"만 났다(피크 0 실측). 5.1 WinRT MediaPlayer 자식도 무음, 미디어 플레이어 경유는 창이 떠서 UX 훼손 | **소리 제거 결정**. 팝업만 표시 |
| **높음** | 윈도 토스트 배너 미표시 | PushNotification 로그에는 `delivered` 로 찍히지만 배너가 억제됨(집중 지원/알림 설정). 앱은 표시 여부를 알 수 없음 | 토스트는 수동 확인용(`notify\send-toast.ps1`). 정식 알림은 자체 팝업 |
| **높음** | `DSH-Notify.exe` 실행 차단 | Smart App Control 이 서명 없는 exe 차단 (CodeIntegrity 3073/3077) | 시작 메뉴 바로가기/스크립트 사용. exe 는 서명·SAC 해제 환경용 |
| 중간 | 완료 팝업은 코어 상주가 전제 | 코어가 꺼져 있으면 요청 파일이 소비되지 않고 남음 | 트레이 앱 실행 상태 유지. 다음 실행 시 첫 tick 에서 소비됨 |
| 중간 | 로그 무한 증가 | `cache\core.log`, `cache\bridge.log` 로테이션 없음 | 수동 삭제. 필요 시 로테이션 추가 |
| 낮음 | OLED 이동폭 고정 | 5px 4방향만 지원 | `ui\popup`/`core.ps1` 상수 수정 |
| 낮음 | digital-7 폰트 라이선스 | 개인용 무료 | 배포 금지. 로컬 사용만 |
| 낮음 | WMP 11 설치해도 WPF MediaPlayer 실패 | 새 Store 앱은 레거시 WMP 구성 요소가 아님 | 사용 안 함 (소리 제거) |

## 6. 진단 로그

| 파일 | 내용 |
|---|---|
| `cache\core.log` | 시작·동기화·UI 반영·팝업 소비·디스패처 예외 |
| `cache\bridge.log` | 플러그인 적용 버전, 수신 이벤트, 완료 판정 |
| `cache\popup-sound.log` | 과거 음향 실험 기록(현재 미사용) |
| `cache\region.json` / `cache\deepseek-peak\holidays.json` | 지역·공휴일 캐시 |
| `cache\audio-policy-backup.reg` | 실험 중 삭제한 PowerShell 앱 오디오 라우팅 백업 |

## 7. 테스트

```powershell
pwsh -NoProfile -File tests\run-all.ps1        # 19 files
pwsh -NoProfile -File tests\docs-contract.ps1   # 헤더/인덱스 검사
node .\bridge\test.mjs                          # 브리지 단위 테스트
```

마지막 결과: **19 files, 19 passed / 0 failed**, docs-contract 47 files PASS.

## 8. 다음 후보 (미착수)

- **클라이언트(브라우저) 오디오**: DSH 웹 GUI에서 `<audio>` 로 재생. spawn 프로세스 오디오 문제를 우회하는 유일한 검증된 경로
- 토스트 AUMID 브랜딩(시작 메뉴 AUMID 등록) — 배너 억제 문제와는 별개
- 코드 서명으로 SAC 통과
- 로그 로테이션, OLED 이동폭/패턴 설정화
- 자동 시작 토글
