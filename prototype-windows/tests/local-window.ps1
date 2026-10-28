<#
.SYNOPSIS    피크/오프피크 구간을 사용자 로컬 시간대로 변환하는 계산을 검증한다.
.DESCRIPTION UTC 고정 구간을 지정한 시간대(TimeZoneInfo)로 변환해, 해외 사용자가
             로컬 시계 기준 구간(예: 미국 태평양 18:00–21:00)으로 볼 수 있는지 확인한다.
             DST(서머타임) 적용 시점과 구간 연속성도 함께 고정한다.
.CONTRACT    providers\deepseek-peak.ps1 — Get-PeakLocalWindow
.INPUTS      없음. providers\deepseek-peak.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 없음 (순수 계산, 네트워크·캐시 미사용).
.TESTS       docs\deepseek-peak-spec.md §4.3 (로컬 시간대 표시)
.NOTES       변환 기준은 기기/지정 시간대이며 공인 IP 가 아니다. 구간 정의는 UTC 고정.
#>

#region INDEX
#   Assert-Window   구간의 로컬 시작/종료/피크 여부 비교
#   Assert-Value    스칼라 기대값 비교
#   New-Utc         UTC DateTime 생성 (Kind=Utc)
#   (main)          W1(PDT) W2(UTC) W3(KST) W4(연속성) W5(PST 겨울)
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$providerPath = Join-Path $repoRoot 'providers\deepseek-peak.ps1'
if (-not (Test-Path -LiteralPath $providerPath)) {
    Write-Host 'RED: providers\deepseek-peak.ps1 이 없습니다.'
    exit 1
}
. $providerPath

$script:Pass = 0
$script:Fail = 0

function New-Utc {
    param([string] $Iso)
    return [datetimeoffset]::Parse($Iso, [cultureinfo]::InvariantCulture).UtcDateTime
}

function Assert-Window {
    param(
        [object] $Window,
        [string] $ExpectedStartLocal,
        [string] $ExpectedEndLocal,
        [bool]   $ExpectedIsPeak,
        [string] $Label
    )

    if ($null -eq $Window) {
        $script:Fail++
        Write-Host "FAIL $Label — 구간 없음"
        return
    }

    $actualStart = ([datetime]$Window.StartLocal).ToString('yyyy-MM-dd HH:mm')
    $actualEnd = ([datetime]$Window.EndLocal).ToString('yyyy-MM-dd HH:mm')
    if ($actualStart -eq $ExpectedStartLocal -and $actualEnd -eq $ExpectedEndLocal -and $Window.IsPeak -eq $ExpectedIsPeak) {
        $script:Pass++
        Write-Host "PASS $Label"
        return
    }

    $script:Fail++
    Write-Host "FAIL $Label — $actualStart~$actualEnd (peak=$($Window.IsPeak)) / 기대 $ExpectedStartLocal~$ExpectedEndLocal (peak=$ExpectedIsPeak)"
}

function Assert-Value {
    param([object] $Actual, [object] $Expected, [string] $Label)

    if ("$Actual" -eq "$Expected") { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$Actual' (기대 '$Expected')"
}

$pacific = [System.TimeZoneInfo]::FindSystemTimeZoneById('Pacific Standard Time')
$korea = [System.TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time')
$utcZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('UTC')

# W1 미국 태평양(PDT, UTC-7): 첫 구간은 '지금~다음 전환', 이어서 UTC 화요일 피크 = 로컬 월요일 18:00–21:00
$w = @(Get-PeakLocalWindow -UtcNow (New-Utc '2026-10-19T16:00:00Z') -HolidayData $null -TimeZone $pacific -Count 4)
Assert-Window -Window $w[0] -ExpectedStartLocal '2026-10-19 09:00' -ExpectedEndLocal '2026-10-19 18:00' -ExpectedIsPeak $false -Label 'W1a PDT 지금~18:00 오프피크'
Assert-Window -Window $w[1] -ExpectedStartLocal '2026-10-19 18:00' -ExpectedEndLocal '2026-10-19 21:00' -ExpectedIsPeak $true -Label 'W1b PDT 18:00–21:00 피크'
Assert-Window -Window $w[2] -ExpectedStartLocal '2026-10-19 21:00' -ExpectedEndLocal '2026-10-19 23:00' -ExpectedIsPeak $false -Label 'W1c PDT 21:00–23:00 오프피크'
Assert-Window -Window $w[3] -ExpectedStartLocal '2026-10-19 23:00' -ExpectedEndLocal '2026-10-20 03:00' -ExpectedIsPeak $true -Label 'W1d PDT 23:00–03:00 (자정 넘김) 피크'

# W2 UTC 시간대: 지금~01:00 오프피크, 01:00–04:00 피크
$w = @(Get-PeakLocalWindow -UtcNow (New-Utc '2026-10-19T16:00:00Z') -HolidayData $null -TimeZone $utcZone -Count 3)
Assert-Window -Window $w[0] -ExpectedStartLocal '2026-10-19 16:00' -ExpectedEndLocal '2026-10-20 01:00' -ExpectedIsPeak $false -Label 'W2a UTC 지금~01:00 오프피크'
Assert-Window -Window $w[1] -ExpectedStartLocal '2026-10-20 01:00' -ExpectedEndLocal '2026-10-20 04:00' -ExpectedIsPeak $true -Label 'W2b UTC 01:00–04:00 피크'
Assert-Window -Window $w[2] -ExpectedStartLocal '2026-10-20 04:00' -ExpectedEndLocal '2026-10-20 06:00' -ExpectedIsPeak $false -Label 'W2c UTC 04:00–06:00 오프피크'

# W3 KST: 10:00–13:00 피크
$w = @(Get-PeakLocalWindow -UtcNow (New-Utc '2026-10-19T16:00:00Z') -HolidayData $null -TimeZone $korea -Count 2)
Assert-Window -Window $w[0] -ExpectedStartLocal '2026-10-20 01:00' -ExpectedEndLocal '2026-10-20 10:00' -ExpectedIsPeak $false -Label 'W3a KST 01:00–10:00 오프피크'
Assert-Window -Window $w[1] -ExpectedStartLocal '2026-10-20 10:00' -ExpectedEndLocal '2026-10-20 13:00' -ExpectedIsPeak $true -Label 'W3b KST 10:00–13:00 피크'

# W4 구간 연속성: 앞 구간 종료 = 다음 구간 시작 (UTC 기준)
$w = @(Get-PeakLocalWindow -UtcNow (New-Utc '2026-10-19T16:00:00Z') -HolidayData $null -TimeZone $korea -Count 4)
$contiguous = $true
for ($i = 0; $i -lt $w.Count - 1; $i++) {
    if ($w[$i].EndUtc -ne $w[$i + 1].StartUtc) { $contiguous = $false }
    if ($w[$i].IsPeak -eq $w[$i + 1].IsPeak) { $contiguous = $false }
}
Assert-Value -Actual $contiguous -Expected $true -Label 'W4 구간 연속·교대'

# W5 PST(겨울, UTC-8): DST 해제 후에도 변환이 맞는지
$w = @(Get-PeakLocalWindow -UtcNow (New-Utc '2026-12-15T02:00:00Z') -HolidayData $null -TimeZone $pacific -Count 2)
Assert-Window -Window $w[0] -ExpectedStartLocal '2026-12-14 18:00' -ExpectedEndLocal '2026-12-14 20:00' -ExpectedIsPeak $true -Label 'W5a PST 18:00–20:00 피크'
Assert-Window -Window $w[1] -ExpectedStartLocal '2026-12-14 20:00' -ExpectedEndLocal '2026-12-14 22:00' -ExpectedIsPeak $false -Label 'W5b PST 20:00–22:00 오프피크'

Write-Host ''
Write-Host "local-window: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
