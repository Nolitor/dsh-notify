<#
.SYNOPSIS    표시 모델 변환(색·표시여부·남은시간·알림 전환)을 검증한다.
.DESCRIPTION 고정 시각과 가짜 상태를 주입해 결정적으로 검사한다. 창/트레이는 그리지 않는다.
.CONTRACT    ui\presenter.ps1 — Get-IndicatorView, Format-PeakRemaining, Test-NotifyTransition
.INPUTS      없음. ui\presenter.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 없음.
.TESTS       docs\2026-10-20-dsh-notify-design.md §2.3, §3.1
.NOTES       Detail 은 매 폴링/틱마다 NextChangeAt 로 다시 계산한다.
#>

#region INDEX
#   New-State    가짜 Get-State 결과
#   Assert-Value 스칼라 비교
#   (main)       P1-P8
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$presenterPath = Join-Path $repoRoot 'ui\presenter.ps1'
if (-not (Test-Path -LiteralPath $presenterPath)) {
    Write-Host 'RED: ui\presenter.ps1 이 없습니다.'
    exit 1
}
. $presenterPath

$script:Pass = 0
$script:Fail = 0

function Assert-Value {
    param([object] $Actual, [object] $Expected, [string] $Label)
    if ("$Actual" -eq "$Expected") { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$Actual' (기대 '$Expected')"
}

function New-State {
    param([string] $Severity, [string] $Headline, [datetime] $NextChangeAt, [string] $Detail = '')
    return [pscustomobject]@{
        Id = 'deepseek-peak'; Label = 'DeepSeek 과금'; Severity = $Severity
        Headline = $Headline; Detail = $Detail; NextChangeAt = $NextChangeAt; NotifyText = ''
    }
}

$now = [datetime]::new(2026, 10, 20, 11, 0, 0)
$peak = New-State -Severity 'alert' -Headline 'PEAK · 100%' -NextChangeAt $now.AddHours(2)
$off = New-State -Severity 'ok' -Headline 'OFF-PEAK · 50%' -NextChangeAt $now.AddHours(1)

# P1 피크 → 빨강, 표시
$v = Get-IndicatorView -State $peak -Config @{ displayMode = 'always' } -Now $now
Assert-Value -Actual $v.Visible -Expected $true -Label 'P1 피크 always → 표시'
Assert-Value -Actual $v.Background -Expected '#B3261E' -Label 'P1b 피크 배경'
Assert-Value -Actual $v.TrayIcon -Expected 'deepseek-red' -Label 'P1c 피크 트레이 red'
Assert-Value -Actual $v.Detail -Expected '→ 다음 구간까지 2h 00m' -Label 'P1d 남은시간 2h 00m'

# P2 오프피크 → 초록
$v = Get-IndicatorView -State $off -Config @{ displayMode = 'always' } -Now $now
Assert-Value -Actual $v.Background -Expected '#1E7B3C' -Label 'P2 오프피크 배경'
Assert-Value -Actual $v.TrayIcon -Expected 'deepseek-green' -Label 'P2b 오프피크 트레이 green'
Assert-Value -Actual $v.Detail -Expected '→ 다음 구간까지 1h 00m' -Label 'P2c 남은시간 1h 00m'

# P3 peakOnly: 오프피크는 숨김
$v = Get-IndicatorView -State $off -Config @{ displayMode = 'peakOnly' } -Now $now
Assert-Value -Actual $v.Visible -Expected $false -Label 'P3 peakOnly 오프피크 숨김'
$v = Get-IndicatorView -State $peak -Config @{ displayMode = 'peakOnly' } -Now $now
Assert-Value -Actual $v.Visible -Expected $true -Label 'P3b peakOnly 피크 표시'

# P4 남은시간 포맷
Assert-Value -Actual (Format-PeakRemaining -NextChangeAt $now.AddMinutes(42) -Now $now) -Expected '42m' -Label 'P4 42m'
Assert-Value -Actual (Format-PeakRemaining -NextChangeAt $now.AddSeconds(30) -Now $now) -Expected '곧 구간 전환' -Label 'P4b 곧 전환'
Assert-Value -Actual (Format-PeakRemaining -NextChangeAt $null -Now $now) -Expected '알 수 없음' -Label 'P4c 미상'

# P5 추정 배지 유지
$est = New-State -Severity 'ok' -Headline 'OFF-PEAK · 50%' -NextChangeAt $now.AddHours(1) -Detail '→ 다음 구간까지 1h 00m (추정)'
$v = Get-IndicatorView -State $est -Config @{} -Now $now
Assert-Value -Actual $v.Detail -Expected '→ 다음 구간까지 1h 00m (추정)' -Label 'P5 추정 배지'

# P6 현지 시간 줄 전달
$v = Get-IndicatorView -State $peak -Config @{} -Now $now -LocalLine '현지 18:00–21:00 (PDT)'
Assert-Value -Actual $v.LocalLine -Expected '현지 18:00–21:00 (PDT)' -Label 'P6 현지 줄'

# P7 불투명도 기본값
$v = Get-IndicatorView -State $peak -Config @{} -Now $now
Assert-Value -Actual $v.Opacity -Expected 0.6 -Label 'P7 기본 불투명도'

# P9 제목: 문장형, 중점 없음
$v = Get-IndicatorView -State $peak -Config @{} -Now $now
Assert-Value -Actual $v.Title -Expected 'DeepSeek Peak (100%)' -Label 'P9 피크 제목'
$v = Get-IndicatorView -State $off -Config @{} -Now $now
Assert-Value -Actual $v.Title -Expected 'DeepSeek Off-Peak (50%)' -Label 'P9b 오프피크 제목'

# P10 타이머 표기 HH:MM:SS (초는 표시 모델에서 분리)
Assert-Value -Actual (Format-PeakTimer -NextChangeAt $now.AddHours(2) -Now $now) -Expected '02:00:00' -Label 'P10 2시간 → 02:00:00'
Assert-Value -Actual (Format-PeakTimer -NextChangeAt $now.AddMinutes(42) -Now $now) -Expected '00:42:00' -Label 'P10b 42분 → 00:42:00'
Assert-Value -Actual (Format-PeakTimer -NextChangeAt $now.AddSeconds(7) -Now $now) -Expected '00:00:07' -Label 'P10c 7초 → 00:00:07'
Assert-Value -Actual (Format-PeakTimer -NextChangeAt $null -Now $now) -Expected '--:--:--' -Label 'P10d 미상 → --:--:--'
$v = Get-IndicatorView -State $peak -Config @{} -Now $now
Assert-Value -Actual $v.TimerText -Expected '02:00:00' -Label 'P10e 표시 모델 타이머'
Assert-Value -Actual $v.TimerMain -Expected '02:00' -Label 'P10f 타이머 본문'
Assert-Value -Actual $v.TimerDim -Expected ':00' -Label 'P10g 타이머 콜론+초(흐림)'

# P8 알림 전환 규칙
Assert-Value -Actual (Test-NotifyTransition -PreviousSeverity 'ok' -CurrentSeverity 'alert') -Expected $true -Label 'P8 ok→alert 알림'
Assert-Value -Actual (Test-NotifyTransition -PreviousSeverity 'alert' -CurrentSeverity 'alert') -Expected $false -Label 'P8b 같은 상태 재알림 없음'
Assert-Value -Actual (Test-NotifyTransition -PreviousSeverity '' -CurrentSeverity 'alert') -Expected $false -Label 'P8c 시작 직후 억제'
Assert-Value -Actual (Test-NotifyTransition -PreviousSeverity 'ok' -CurrentSeverity 'alert' -NotifyOnChange $false) -Expected $false -Label 'P8d 설정으로 끔'

Write-Host ''
Write-Host "presenter: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
