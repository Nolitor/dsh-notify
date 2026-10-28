<#
.SYNOPSIS    DSH Notify 윈도우 위젯의 포터블 패키지를 만든다.
.DESCRIPTION app\, providers\, ui\ 스크립트와 무음 진입점 launch.js를 dist\DSH-Notify-Portable에 모으고,
             금지 에셋(Digital-7/DeepSeek 로고/ding.wav/exe/vbs)을 제외한다. ZIP과 SHA256을 만든다.
.CONTRACT    core.ps1, app\font-loader.ps1, app\tray.ps1, launch.js, start.cmd
.INPUTS      -Version(기본 0.2.0), -OutRoot(기본 dist)
.OUTPUTS     dist\DSH-Notify-Portable\, dist\DSH-Notify-Portable-<version>.zip, SHA256SUMS.txt
.SIDE-EFFECTS dist 폴더 생성/덮어쓰기.
.TESTS       tests\portable-package.ps1
.NOTES       공개 패키지에는 사용자 config/cache/fonts를 넣지 않는다.
#>

#region INDEX
#   Copy-RuntimeFile  런타임 파일 복사
#   (main)            stage → README/LICENSE → zip → SHA256
#endregion

param(
    [string] $Version = '0.2.0',
    [string] $OutRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $repoRoot 'dist' }
$target = Join-Path $OutRoot 'DSH-Notify-Portable'
if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
New-Item -ItemType Directory -Path $target -Force | Out-Null

function Copy-RuntimeFile {
    param([string] $Relative, [string] $DestinationRoot = $target)
    $source = Join-Path $repoRoot $Relative
    if (-not (Test-Path -LiteralPath $source)) { return }
    $destination = Join-Path $DestinationRoot $Relative
    $directory = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

foreach ($file in @('core.ps1', 'config.ps1', 'launch.js', 'start.cmd', 'LICENSE')) {
    Copy-RuntimeFile -Relative $file
}
foreach ($file in @('app\font-loader.ps1', 'app\tray.ps1')) {
    Copy-RuntimeFile -Relative $file
}
foreach ($file in @('ui\presenter.ps1', 'ui\indicator.ps1', 'ui\popup.ps1', 'ui\build-neutral-icons.ps1')) {
    Copy-RuntimeFile -Relative $file
}
Copy-RuntimeFile -Relative 'ui\icons\neutral-green.ico'
Copy-RuntimeFile -Relative 'ui\icons\neutral-red.ico'
foreach ($file in @('providers\deepseek-peak.ps1', 'providers\_template.ps1')) {
    Copy-RuntimeFile -Relative $file
}
foreach ($file in @('notify\toast.ps1', 'notify\send-toast.ps1', 'notify\popup.ps1', 'notify\peak-alert.ps1')) {
    Copy-RuntimeFile -Relative $file
}
New-Item -ItemType Directory -Path (Join-Path $target 'fonts') -Force | Out-Null

$readme = @'
DSH Notify — Windows Off-Peak Widget
====================================

요구 사항
- Windows 10/11
- PowerShell 7 이상 (pwsh.exe)
  설치: Windows Terminal에서 `winget install Microsoft.PowerShell`

브라우저 호환성 (웹 알림 플러그인)
- 공식 지원/검증: Chromium 계열(Chrome, Edge, Whale, Brave) — OS 알림 배너·고유 태그·Web Audio·시스템 알림음.
- Firefox: 엄격한 Autoplay 정책으로 주소창의 '오디오 및 비디오 자동 재생 허용'을 켜지 않으면 비동기 완료음이 무음이 될 수 있습니다.
- Safari(macOS/iOS): 백그라운드 탭 동결 및 사용자 제스처 미디어 정책으로 백그라운드 사운드가 제한될 수 있습니다.
- Chromium 외 브라우저는 동작을 보증하지 않으며 Chromium 기반 사용을 권장합니다.

🔊 소리가 나지 않을 때 (최초 1회 브라우저 설정 및 오디오 엔진 갱신):
1. 브라우저 주소창 왼쪽의 설정(조율기/자물쇠) 아이콘 클릭 → '사이트 설정'
2. '소리' 항목을 자동(기본값)에서 '허용'으로 변경
3. 단순 새로고침(F5)으로는 크롬 백그라운드 오디오 서비스가 갱신되지 않을 수 있으므로,
   주소창에 chrome://restart를 입력하여 브라우저를 완전히 재시작한 뒤 사용

실행
1. 이 폴더를 원하는 위치에 압축 해제합니다.
2. launch.js를 더블클릭합니다. (Windows Script Host/JScript, 콘솔 창 없음)
   - start.cmd는 디버그/복구용 폴백입니다. 이 파일을 더블클릭하면 cmd 창이 잠깐 보일 수 있습니다.
   - 관리자 권한은 필요하지 않습니다.
   - 관리자 셸에서 실행하면 launch.js가 Explorer를 통해 일반 권한으로 다시 실행합니다(UIPI 방어).
3. 트레이 아이콘 우클릭 → "부팅 시 자동 실행"을 켜면 사용자 시작프로그램 폴더에 바로가기가 생성됩니다.
   - 바로가기는 wscript.exe → launch.js를 가리키므로 부팅 시 콘솔이 뜨지 않습니다.
   - 레지스트리/UAC를 사용하지 않습니다.
   - 끄면 바로가기가 삭제됩니다.

폰트 (BYO)
- 기본은 Consolas/Segoe UI 시스템 폰트입니다.
- Digital-7 등 외부 폰트를 쓰려면 .ttf/.otf 파일을 위젯 창 위로 끌어다 놓으세요.
- 폰트는 `fonts\custom\`에 저장되고 즉시 적용됩니다. 라이선스 책임은 사용자에게 있습니다.
- 앱 폴더가 쓰기 불가면 %LOCALAPPDATA%\DSH-Notify\fonts\로 저장됩니다.

데이터
- 설정/캐시는 앱 폴더가 쓰기 가능하면 그곳에, 아니면 %LOCALAPPDATA%\DSH-Notify\에 저장됩니다.
- 제거: 트레이에서 자동 실행을 끄고, 이 폴더를 삭제합니다.

라이선스
- MIT. LICENSE 참조.
- 폰트/로고/오디오 파일을 기본 번들하지 않습니다.
'@
Set-Content -LiteralPath (Join-Path $target 'README.txt') -Value $readme -Encoding UTF8

$notices = @'
DSH Notify — Third-Party Notices

이 패키지는 다음 에셋을 포함하지 않습니다.
- Digital-7 폰트 (사용자 BYO)
- DeepSeek 공식 로고/아이콘
- ding.wav 등 오디오 파일

기본 아이콘은 이 프로젝트가 MIT로 배포하는 중립 시계 SVG/ICO입니다.
사용자가 주입한 폰트/아이콘/오디오의 라이선스 책임은 사용자에게 있습니다.
'@
Set-Content -LiteralPath (Join-Path $target 'THIRD-PARTY-NOTICES.md') -Value $notices -Encoding UTF8

$zip = Join-Path $OutRoot ("DSH-Notify-Portable-$Version.zip")
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $target '*') -DestinationPath $zip -Force
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
Set-Content -LiteralPath (Join-Path $OutRoot 'SHA256SUMS.txt') -Value ("{0}  {1}" -f $hash, (Split-Path -Leaf $zip)) -Encoding ASCII

Write-Host "OK: $target"
Write-Host "ZIP: $zip"
Write-Host "SHA256: $hash"
