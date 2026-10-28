<#
.SYNOPSIS    상주 앱 설정 로드/저장과 표시 보조 계산을 검증한다.
.DESCRIPTION 기본값·부분 병합·손상 JSON·원자적 저장·위치 클램프·현지 시간 줄 형식을 확인한다.
.CONTRACT    config.ps1 — Get-NotifyConfig, Save-NotifyConfig, Get-ClampedPosition, Format-RegionWindow
.INPUTS      없음. config.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 임시 디렉터리 생성·삭제.
.TESTS       docs\2026-10-20-dsh-notify-design.md §4 (설정), §3.1 (현지 줄)
.NOTES       displayMode 는 'always' | 'peakOnly'. peakOnly 는 오프피크에 카드를 숨긴다.
#>

#region INDEX
#   New-TempDir   임시 설정 디렉터리
#   Assert-Value  스칼라 비교
#   (main)        C1-C6
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot 'config.ps1'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host 'RED: config.ps1 이 없습니다.'
    exit 1
}
. $configPath

$script:Pass = 0
$script:Fail = 0

function Assert-Value {
    param([object] $Actual, [object] $Expected, [string] $Label)
    if ("$Actual" -eq "$Expected") { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$Actual' (기대 '$Expected')"
}

function New-TempDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-config-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

$tmp = New-TempDir
try {
    # C1 파일 없음 → 기본값
    $cfg = Get-NotifyConfig -Path (Join-Path $tmp 'none.json')
    Assert-Value -Actual $cfg.DisplayMode -Expected 'always' -Label 'C1 기본 표시 모드'
    Assert-Value -Actual $cfg.Opacity -Expected 0.6 -Label 'C1b 기본 불투명도'
    Assert-Value -Actual "$($cfg.PositionX),$($cfg.PositionY)" -Expected '40,40' -Label 'C1c 기본 위치'
    Assert-Value -Actual $cfg.ProviderConfig['refreshHours'] -Expected 240 -Label 'C1d provider 기본 갱신 주기'
    Assert-Value -Actual $cfg.Notifications -Expected $true -Label 'C1e 기본 알림 켜짐'
    Assert-Value -Actual $cfg.OledProtection -Expected $false -Label 'C1f 기본 OLED 보호 꺼짐'
    Assert-Value -Actual $cfg.OledIntervalSeconds -Expected 60 -Label 'C1g 기본 OLED 간격'

    # C2 부분 설정 병합 (peakOnly + 위치 + provider 옵션)
    $path = Join-Path $tmp 'config.json'
    @'
{
  "displayMode": "peakOnly",
  "opacity": 0.7,
  "position": { "x": 120, "y": 80 },
  "notifyOnChange": false,
  "notifications": false,
  "oledProtection": true,
  "oledIntervalSeconds": 5,
  "providers": { "deepseek-peak": { "treatMakeupAsPeak": false, "refreshHours": 24 } }
}
'@ | Set-Content -LiteralPath $path -Encoding UTF8
    $cfg = Get-NotifyConfig -Path $path
    Assert-Value -Actual $cfg.DisplayMode -Expected 'peakOnly' -Label 'C2 peakOnly 병합'
    Assert-Value -Actual $cfg.Opacity -Expected 0.7 -Label 'C2b 불투명도 병합'
    Assert-Value -Actual "$($cfg.PositionX),$($cfg.PositionY)" -Expected '120,80' -Label 'C2c 위치 병합'
    Assert-Value -Actual $cfg.NotifyOnChange -Expected $false -Label 'C2d 알림 설정 병합'
    Assert-Value -Actual $cfg.Notifications -Expected $false -Label 'C2d2 알림 스위치 병합'
    Assert-Value -Actual $cfg.OledProtection -Expected $true -Label 'C2d3 OLED 보호 병합'
    Assert-Value -Actual $cfg.OledIntervalSeconds -Expected 5 -Label 'C2d4 OLED 간격 병합'
    Assert-Value -Actual $cfg.ProviderConfig['treatMakeupAsPeak'] -Expected $false -Label 'C2e provider 플래그 병합'
    Assert-Value -Actual $cfg.Warning -Expected '' -Label 'C2f 경고 없음'

    # C3 손상 JSON → 기본값 + 경고
    $bad = Join-Path $tmp 'bad.json'
    '{ "displayMode": "peakOnly", ' | Set-Content -LiteralPath $bad -Encoding UTF8
    $cfg = Get-NotifyConfig -Path $bad
    Assert-Value -Actual $cfg.DisplayMode -Expected 'always' -Label 'C3 손상 → 기본값'
    Assert-Value -Actual ($cfg.Warning -ne '') -Expected $true -Label 'C3b 경고 표시'

    # C4 저장 왕복 (원자적 파일 교체)
    $savePath = Join-Path $tmp 'saved.json'
    $cfg = Get-NotifyConfig -Path (Join-Path $tmp 'none.json')
    $cfg.DisplayMode = 'peakOnly'
    $cfg.PositionX = 200
    $cfg.PositionY = 150
    $cfg.Notifications = $false
    $cfg.OledProtection = $true
    Save-NotifyConfig -Path $savePath -Config $cfg
    $reload = Get-NotifyConfig -Path $savePath
    Assert-Value -Actual $reload.DisplayMode -Expected 'peakOnly' -Label 'C4 저장→로드 표시 모드'
    Assert-Value -Actual "$($reload.PositionX),$($reload.PositionY)" -Expected '200,150' -Label 'C4b 저장→로드 위치'
    Assert-Value -Actual $reload.Notifications -Expected $false -Label 'C4d 저장→로드 알림 스위치'
    Assert-Value -Actual $reload.OledProtection -Expected $true -Label 'C4e 저장→로드 OLED 보호'
    Assert-Value -Actual (Test-Path "$savePath.tmp") -Expected $false -Label 'C4c 임시 파일 잔여 없음'

    # C5 위치 클램프 (화면 밖 → 기본값)
    $bounds = New-Object System.Drawing.Rectangle(0, 0, 1920, 1080)
    $pos = Get-ClampedPosition -X 100 -Y 90 -Bounds $bounds -DefaultX 40 -DefaultY 40
    Assert-Value -Actual "$($pos.X),$($pos.Y)" -Expected '100,90' -Label 'C5 화면 안 위치 유지'
    $pos = Get-ClampedPosition -X -5000 -Y -5000 -Bounds $bounds -DefaultX 40 -DefaultY 40
    Assert-Value -Actual "$($pos.X),$($pos.Y)" -Expected '40,40' -Label 'C5b 화면 밖 → 기본값'

    # C6 현지 시간 줄 (PDT)
    $la = [System.TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles')
    $line = Format-RegionWindow -UtcNow ([datetime]::SpecifyKind([datetime]::new(2026, 10, 20, 1, 0, 0), 'Utc')) `
        -NextChangeAt ([datetime]::SpecifyKind([datetime]::new(2026, 10, 20, 4, 0, 0), 'Utc')) -TimeZone $la
    Assert-Value -Actual $line -Expected 'Local 18:00–21:00 (UTC-7)' -Label 'C6 현지 시간 줄'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "core-config: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
