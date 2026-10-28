# 윈도우 오프피크 위젯 — Phase 2 PoC 실측 보고서

> 상태: proposed · 최종 갱신: 2026-10-23 · git: main @ 8fb5b58 · 상위: [README.md](../README.md)

- 범위: 모듈 A(윈도우 위젯)의 PowerShell 7 기준선, WPF Drag & Drop 폰트 주입, UIPI, `start.cmd` 포터블 실행.
- 이번 단계에서는 **제품 코드를 수정하지 않았다.** PoC는 `%TEMP%`에서 실행 후 삭제했다.
- 5.1 다운그레이드는 기각한다. 기준선은 **PowerShell 7+ (`pwsh.exe`)** 이다.

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 결론 | WPF 드롭/폰트 리바인딩은 PoC 통과. 실제 Explorer 드래그 1회 수동 확인만 남음 |
| 2 | 기준선 | pwsh 7.6.7, 5.1 포팅 폐기 |
| 3 | WPF D&D | AllowDrop·FileDrop·저장·Unblock·FontFamily 리바인딩 검증 |
| 4 | UIPI | High → Explorer 경유 Medium 재실행으로 회피 |
| 5 | 저장·MOTW | Program Files 거부, LocalAppData/앱 폴더 성공, Zone.Identifier 제거 |
| 6 | start.cmd | pwsh 가드 + Bypass + Hidden WPF 구동 확인 |
| 7 | 구현 계획 | font-loader, D&D 이벤트, 데이터 루트, 패키징 |
| 8 | 리스크·다음 | 실제 OLE 드래그, 폰트 파서, 콘솔 깜빡임 |

---

## 1. 결론

**PoC 판정: 조건부 Go.** 핵심 기능은 구현 가능하다.

| 항목 | 판정 | 근거 |
|---|---|---|
| WPF `AllowDrop`/`Drop` 수신 | **통과** | 합성 `DragEventArgs`로 `FileDrop` 1개 수신, 핸들러 실행 |
| 드롭 파일 저장 + MOTW 해제 | **통과** | `fonts/` 복사, `Zone.Identifier` 제거 확인 |
| 런타임 폰트 전환 | **통과** | 재시작 없이 `FontFamily` 교체, typefaces 4개 로드 |
| 기본 시스템 폰트 | **통과** | Consolas/Segoe UI로 초기 렌더링 |
| 임의 파일명 폰트 패밀리 탐색 | **통과** | `Fonts.GetFontFamilies`/GDI+로 `Digital-7` 식별 |
| 저장 경로 폴백 | **통과** | Medium 권한에서 Program Files 쓰기 거부, LocalAppData/앱 폴더 성공 |
| UIPI 회피 | **통과** | High 셸 → Explorer 경유 Medium 자식 실행 확인 |
| `start.cmd` WPF 구동 | **통과** | `where pwsh`, Bypass, Hidden, WPF Loaded/Tick 확인 |
| 실제 Explorer 마우스 드래그 | **미확인** | 자동화 드래그가 drop을 만들지 못함. 수동 1회 확인 필요 |

**남은 조건:** 실제 Explorer에서 폰트 파일을 위젯 위로 끌어다 놓는 **수동 1회 확인**. WPF 표준 OLE 드롭 경로이고 합성 이벤트는 통과했으므로 구현 리스크는 낮다. 다만 자동화로 재현하지 못한 것은 사실이다.

---

## 2. 기준선: PowerShell 7

| 항목 | 값 |
|---|---|
| OS | Windows 11 10.0.26300 |
| PowerShell | **7.6.7** (`pwsh`) |
| 현재 셸 무결성 | **High (관리자)** |
| Explorer 무결성 | Medium |
| `Start-ThreadJob` | 사용 가능 |
| `ConvertFrom-Json -AsHashtable` | 사용 가능 |
| WPF/DispatcherTimer | 정상 |

### 5.1을 기각한 이유(실측)

- 5.1에서는 `Start-ThreadJob` 없음, `-AsHashtable` 없음.
- 36/41 스크립트가 UTF-8 BOM 없이 저장되어 5.1에서 한글 파싱이 깨지는 사례가 다수 확인됨.
- 5.1/.NET Framework는 `America/Los_Angeles` 같은 IANA 시간대 ID를 찾지 못함(`TimeZoneNotFoundException`). 현재 provider는 기기 시간대로 폴백하지만 지역 줄 기능이 손실된다.
- `Start-Job`/해시테이블 변환 자체는 5.1에서 가능했지만, 위 두 문제를 제품 코드에 우겨넣는 것은 아키텍처 오염이다.
- **결론: 5.1 포팅 중단. `pwsh` 7 필수. 기존 `Start-ThreadJob`/`-AsHashtable` 유지.**

---

## 3. WPF Drag & Drop 폰트 주입

### 3.1 검증한 경로

```
Window.AllowDrop = true
  → Drop 이벤트
  → e.Data.GetData([DataFormats]::FileDrop)
  → .ttf/.otf 검사
  → Unblock-File
  → fonts/ (또는 LocalAppData 폴백) 복사
  → FontFamily 재생성
  → TextBlock.FontFamily 교체
```

### 3.2 실측 결과

| 항목 | 결과 |
|---|---|
| `AllowDrop` 설정 | `True` 확인 |
| Drop 이벤트 등록 | `Add_Drop` 등록, 합성 이벤트에서 실행 |
| `DataFormats.FileDrop` | 파일 1개 수신 |
| 파일 복사 | `fonts/digital-7.ttf` 생성 |
| MOTW 제거 | `Zone.Identifier` 제거 확인 |
| 폰트 로드 | `FontFamily` typefaces 4개 |
| 런타임 전환 | `Consolas` → `./#Digital-7`, 재시작 없음 |
| 경로 공백/한글 | `DSH Font Test 한글` 경로에서 typefaces 4개 |
| 기본 폰트 | `Consolas`/`Segoe UI` 정상 |

### 3.3 폰트 패밀리 이름 탐색

BYO 폰트는 파일명과 패밀리명이 다를 수 있다. 두 방법 모두 동작했다.

```powershell
# 방법 A: 폴더의 폰트 패밀리 열거
[System.Windows.Media.Fonts]::GetFontFamilies([Uri]$folder)
# → ./#Digital-7

# 방법 B: 파일에서 직접 패밀리명 추출
$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$pfc.Families[0].Name
# → Digital-7
```

권장: 파일 단위로 격리 폴더(`fonts/custom/<id>/`)에 복사한 뒤 방법 A로 열거하고, 실패하면 방법 B로 폰트 패밀리를 얻는다. 방법 B는 GDI+ 로드이므로 예외 처리가 필요하다.

### 3.4 실제 Explorer 드래그 상태

- 합성 `DragEventArgs`(`DragDrop.DropEvent`)로 Drop 핸들러/저장/폰트 리바인딩은 검증했다.
- 실제 Explorer 파일 아이콘에서 WPF 창으로 마우스 드래그하는 자동화는 여러 번 시도했으나 drop이 발생하지 않았다. DPI 200% 좌표 보정 후에도 재현되지 않았다.
- 이는 WPF 드롭 구현 문제인지, 자동화 마우스 주입/Explorer OLE 드래그 문제인지 분리하지 못했다.
- **따라서 실제 Explorer 드래그 1회는 수동 검증 항목으로 남긴다.** WPF의 표준 `AllowDrop`/`FileDrop` 경로이고 합성 이벤트는 통과했으므로 구현 자체의 리스크는 낮다.

**후속 수정(2026-10-23):** 실제 마우스 드롭 무반응을 막기 위해 `Drop` 대신 `PreviewDrop`/`PreviewDragOver`를
Window와 Border 양쪽에 등록하고, `AllowDrop`을 둘 다 보장했다. 또한 `ChangeWindowMessageFilterEx`로
`WM_DROPFILES`/`WM_COPYDATA`/`0x0049`를 허용하고, `cache/core.log`에 `font-drop:` 진입/예외 로그를 추가했다.
합성 `PreviewDrop`으로 FontFamily 전환과 로그를 확인했으며, 실제 Explorer 드래그는 수동 확인 항목이다.

---

## 4. UIPI 권한 간섭

### 4.1 실측

- 현재 DSH 셸: **High Mandatory Level** (`S-1-16-12288`). 여기서 앱을 직접 띄우면 High가 된다.
- Explorer: **Medium** (`S-1-16-8192`).
- High 앱은 Explorer(Medium)에서 오는 OLE 드롭을 UIPI로 차단한다.
- `runas /trustlevel:0x20000`은 이 환경에서 **High를 유지**했다. 신뢰할 수 있는 de-elevation 수단이 아니다.
- **Explorer 경유 실행은 Medium을 만들었다.** `explorer.exe "start.cmd"`로 재실행하면 Medium 자식이 뜨고, 그 자식에서 `pwsh -v`도 정상 동작했다.

### 4.2 권장 가드

`start.cmd`:

```bat
@echo off
whoami /groups | findstr /C:"S-1-16-12288" >nul
if not errorlevel 1 (
  explorer.exe "%~f0"
  exit /b
)
where pwsh >nul 2>&1
if errorlevel 1 (
  echo PowerShell 7이 필요합니다.
  echo Windows Terminal에서: winget install Microsoft.PowerShell
  exit /b 1
)
pwsh -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File "%~dp0app\core.ps1"
```

- High에서 실행되면 Explorer를 통해 자기 자신을 다시 띄워 **Medium**으로 전환한다.
- `core.ps1`을 관리자 셸에서 직접 실행하는 경로도 막아야 한다. 시작 시 High를 감지하면 “D&D가 차단될 수 있으니 `start.cmd`로 실행하세요” 경고를 표시하거나, D&D를 비활성화한다.
- 자동 재실행은 `start.cmd`에서만 수행하고, `core.ps1`은 무한 루프를 피하기 위해 경고만 한다.

---

## 5. 저장 경로·MOTW

### 5.1 Medium 권한 쓰기 실측

| 경로 | 결과 |
|---|---|
| `C:\Program Files\<test>` | **Access denied** |
| `%LOCALAPPDATA%\DSH-Notify\...` | 성공 |
| 앱 폴더 `fonts\` | 성공 |

**폴백 규칙:**

1. 앱 루트 `fonts\`가 쓰기 가능하면 그곳 사용.
2. 쓰기 불가(Program Files 등)면 `%LOCALAPPDATA%\DSH-Notify\fonts\` 사용.
3. 둘 다 실패하면 드롭을 거부하고 사용자에게 경로를 안내.

> 폰트뿐 아니라 `config.json`/`cache`도 같은 문제를 가진다. 공개 패키지는 **코드 루트와 데이터 루트를 분리**하고, 데이터는 앱 폴더가 쓰기 가능하면 그곳, 아니면 `%LOCALAPPDATA%\DSH-Notify`를 사용해야 한다. 이번 모듈 A 구현에서 함께 정리한다.

### 5.2 MOTW

- `Zone.Identifier`가 붙은 `.ttf`를 `Unblock-File`로 처리한 뒤 WPF에서 로드했다.
- `Zone.Identifier` 스트림이 제거된 것을 확인했다.
- 드롭 핸들러에서 복사 전/후 `Unblock-File -LiteralPath`를 호출한다. 실패해도 폰트 로드는 시도하고, 실패 시 조용히 기본 폰트로 폴백한다.

### 5.3 폰트 파일 안전성

- 허용 확장자: `.ttf`, `.otf`.
- 크기 제한: 5MB 이하 권장.
- 파일명은 `[IO.Path]::GetFileName`으로 정규화하고, 격리 폴더에 저장.
- WPF/GDI+ 로드 예외를 모두 잡고 기본 폰트로 폴백.
- 폰트 파일은 시스템에 설치하지 않는다. `PrivateFontCollection`/URI 로드만 사용한다.

---

## 6. start.cmd 포터블 실행

### 6.1 검증

| 항목 | 결과 |
|---|---|
| `where pwsh` | 7.6.7 발견 |
| High → Explorer 재실행 | Medium 자식 확인 |
| `pwsh -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File` | WPF 창 Loaded/Tick/종료 확인 |
| 경로 공백 | 인용 처리로 동작 |
| 관리자 권한 요구 | 없음 |

### 6.2 콘솔 깜빡임

- `start.cmd` 자체는 콘솔 앱이므로 **최초 더블클릭 시 cmd 창이 짧게 보인다.**
- `-WindowStyle Hidden`은 그 자식 `pwsh` 콘솔을 숨긴다. WPF 창은 정상 표시된다.
- 일상 실행은 `start.cmd`가 생성한 `.lnk`(WindowStyle 7, 대상 `start.cmd` 또는 `pwsh`)를 쓰는 것이 좋다.
- “완전 무콘솔”이 필요하면 `.lnk`가 정답이며, `.cmd` 단일 파일만으로 0ms 플래시를 보장하기는 어렵다.

### 6.3 pwsh 미설치 메시지

```text
PowerShell 7이 필요합니다.
Windows Terminal에서 다음 명령어로 설치할 수 있습니다:
winget install Microsoft.PowerShell
```

- `where pwsh`가 실패하면 위 메시지를 출력하고 `exit /b 1`.
- Store 앱 별칭 경로가 아닌 `where` 결과를 사용한다.

---

## 7. 구현 계획

### 7.1 파일 추가

```
app/
  core.ps1
  config.ps1
  providers/
  ui/
    font-loader.ps1     # 신규
    indicator.ps1
    ...
start.cmd
install-startup.cmd
uninstall-startup.cmd
README.txt
LICENSE
THIRD-PARTY-NOTICES.md
```

### 7.2 font-loader.ps1 책임

- `Get-FontStorePath` — 앱 `fonts` 쓰기 테스트 → LocalAppData 폴백.
- `Test-FontCandidate` — `.ttf/.otf`, 크기, 존재.
- `Import-FontFile` — Unblock, 격리 폴더 복사, 패밀리 탐색, `FontFamily` 반환.
- `Get-DefaultFontFamily` — `Consolas` → `Segoe UI` → `Segoe UI Variable` → 시스템 기본.
- `Set-WidgetFont` — `$script:TimerFontFamily` 갱신 + 기존 TextBlock 재바인딩.
- `Initialize-CustomFont` — 시작 시 저장된 폰트 로드, 실패 시 기본.

### 7.3 D&D 이벤트

- `core.ps1`의 메인 Window에 `AllowDrop = $true`.
- `DragEnter`/`DragOver`: `FileDrop`에 `.ttf/.otf`가 있으면 `e.Effects = Copy`, 아니면 `None`.
- `Drop`: 첫 유효 파일만 처리, 성공 시 짧은 토스트/카드 테두리 피드백.
- 실패 시 기존 폰트 유지, 콘솔/트레이 로그.
- 드롭 후 `$script:config.CustomFont` 저장.

### 7.4 UIPI·데이터 루트

- `start.cmd` High → Explorer 재실행.
- `core.ps1` 시작 시 High 감지 → 경고 + D&D 비활성(또는 start.cmd 안내).
- config/cache/fonts 모두 쓰기 가능한 데이터 루트 결정. 앱 루트가 읽기 전용이면 LocalAppData로 폴백.

### 7.5 테스트

| 테스트 | 방법 |
|---|---|
| Drop 핸들러 | 합성 `DragEventArgs` + FileDrop |
| 실제 Explorer 드래그 | 수동 1회 |
| MOTW | Zone.Identifier 생성 → Drop → 스트림 제거 확인 |
| 폰트 리바인딩 | Consolas → custom, typefaces 수 확인 |
| 임의 파일명 | `random-name.ttf` + 패밀리 탐색 |
| 저장 폴백 | Program Files 거부 / LocalAppData 성공 |
| UIPI | High 셸 → start.cmd → Medium 확인 + 수동 드래그 |
| pwsh 가드 | PATH에서 pwsh 제거 후 메시지 확인 |
| 기본 폰트 | 폰트 없이 Consolas/Segoe UI 렌더링 |

---

## 8. 리스크·다음 단계

| 리스크 | 영향 | 완화 |
|---|---|---|
| 실제 Explorer OLE 드래그 미확인 | UX 핵심 | 수동 1회 확인 후 구현 확정 |
| High 앱에서 D&D 차단 | 기능 불가 | start.cmd 자동 Medium 재실행 + core.ps1 경고 |
| `runas /trustlevel` 불안정 | — | 사용하지 않음. Explorer 경유만 사용 |
| 폰트 파서 예외/악성 파일 | 앱 크래시 | 확장자/크기 제한, try/catch, 기본 폰트 폴백 |
| 패밀리명 탐색 실패 | 폰트 미적용 | GDI+ → Fonts.GetFontFamilies 순차 시도 |
| 앱 루트 읽기 전용 | 설정/폰트 저장 실패 | 데이터 루트 LocalAppData 폴백 |
| cmd 콘솔 깜빡임 | 첫 실행 UX | 최초 1회 허용, 일상은 생성된 `.lnk` |
| pwsh 미설치 | 실행 불가 | `where pwsh` 가드 + winget 안내 |
| 5.1 회귀 유혹 | 아키텍처 오염 | 기준선 pwsh 7 고정, 5.1 분기 금지 |

**다음 단계:** 위 PoC 결과를 승인하면 모듈 A를 `pwsh 7` 기준으로 구현한다. 순서는 ① `font-loader.ps1` + 단위 PoC, ② `core.ps1` D&D 연결 및 동적 리바인딩, ③ `start.cmd`/UIPI 가드, ④ 포터블 패키징·테스트.
