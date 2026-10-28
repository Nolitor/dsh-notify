<#
.SYNOPSIS    DeepSeek 과금 구간 판정(Get-PeakDecision)과 다음 전환 시각을 표 기반으로 검증한다.
.DESCRIPTION 픽스처 공휴일 데이터를 인라인 주입하므로 네트워크가 필요 없다.
             KST 입력을 UTC 로 변환해 판정하고, IsPeak·Reason·Confidence 를 모두 확인한다.
             경계 시각(피크 창 시작/끝)과 대체근무일 양쪽 해석, 다음 전환 시각을 포함한다.
.CONTRACT    providers\deepseek-peak.ps1 — Get-PeakDecision, Get-PeakNextChange
.INPUTS      없음. providers\deepseek-peak.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 케이스 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 없음 (네트워크·캐시 미사용).
.TESTS       docs\deepseek-peak-spec.md §5 표 + 경계 + §4.1 다음 전환
.NOTES       KST = UTC+9, 서머타임 없음.
#>

#region INDEX
#   New-KstUtc          KST ISO 문자열 → UTC DateTime(Kind=Utc)
#   New-Holiday2026     2026 공휴일 픽스처 (국경절·대체근무일 포함)
#   Assert-Decision     판정 결과(IsPeak/Reason/Confidence) 비교
#   Assert-NextChange   다음 전환 시각 비교
#   (main)              표 1~9 + 경계 6 + 다음 전환 3
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$providerPath = Join-Path $repoRoot 'providers\deepseek-peak.ps1'

if (-not (Test-Path -LiteralPath $providerPath)) {
    Write-Host 'RED: providers\deepseek-peak.ps1 이 없습니다 — 구현 전에는 실패해야 합니다.'
    Write-Host 'FAIL peak-decisions: 0 passed / 0 failed (provider missing)'
    exit 1
}

. $providerPath

$script:Pass = 0
$script:Fail = 0

function New-KstUtc {
    param([string] $Local)
    return [datetimeoffset]::Parse($Local, [cultureinfo]::InvariantCulture).UtcDateTime
}

function New-Holiday2026 {
    $days = [System.Collections.Generic.List[object]]::new()

    foreach ($d in 1..3)     { $days.Add([pscustomobject]@{ name = '元旦'; date = "2026-01-$('{0:00}' -f $d)"; isOffDay = $true }) }
    foreach ($d in 15..23)   { $days.Add([pscustomobject]@{ name = '春节'; date = "2026-02-$('{0:00}' -f $d)"; isOffDay = $true }) }
    foreach ($d in 4..6)     { $days.Add([pscustomobject]@{ name = '清明节'; date = "2026-04-$('{0:00}' -f $d)"; isOffDay = $true }) }
    foreach ($d in 1..5)     { $days.Add([pscustomobject]@{ name = '劳动节'; date = "2026-05-$('{0:00}' -f $d)"; isOffDay = $true }) }
    foreach ($d in 19..21)   { $days.Add([pscustomobject]@{ name = '端午节'; date = "2026-06-$('{0:00}' -f $d)"; isOffDay = $true }) }
    foreach ($d in 25..27)   { $days.Add([pscustomobject]@{ name = '中秋节'; date = "2026-09-$('{0:00}' -f $d)"; isOffDay = $true }) }
    foreach ($d in 1..7)     { $days.Add([pscustomobject]@{ name = '国庆节'; date = "2026-10-$('{0:00}' -f $d)"; isOffDay = $true }) }

    # 대체근무일 (isOffDay: false) — 주말이지만 근무일
    $days.Add([pscustomobject]@{ name = '元旦';   date = '2026-01-04'; isOffDay = $false })
    $days.Add([pscustomobject]@{ name = '春节';   date = '2026-02-14'; isOffDay = $false })
    $days.Add([pscustomobject]@{ name = '春节';   date = '2026-02-28'; isOffDay = $false })
    $days.Add([pscustomobject]@{ name = '劳动节'; date = '2026-05-09'; isOffDay = $false })
    $days.Add([pscustomobject]@{ name = '国庆节'; date = '2026-09-20'; isOffDay = $false })
    $days.Add([pscustomobject]@{ name = '国庆节'; date = '2026-10-10'; isOffDay = $false })

    return [pscustomobject]@{
        year   = 2026
        papers = @('https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm')
        days   = $days.ToArray()
    }
}

function New-Holiday2027Empty {
    return [pscustomobject]@{ year = 2027; papers = @(); days = @() }
}

function Assert-Decision {
    param(
        [string] $Label,
        [string] $KstLocal,
        [object] $Holiday,
        [bool]   $TreatMakeupAsPeak = $true,
        [bool]   $ExpectIsPeak,
        [string] $ExpectReason,
        [string] $ExpectConfidence
    )

    $utc = New-KstUtc -Local $KstLocal
    try {
        $actual = Get-PeakDecision -UtcNow $utc -HolidayData $Holiday -TreatMakeupAsPeak $TreatMakeupAsPeak
    }
    catch {
        $script:Fail++
        Write-Host "FAIL $Label — 예외: $($_.Exception.Message)"
        return
    }

    $problems = @()
    if ($actual.IsPeak -ne $ExpectIsPeak) { $problems += "IsPeak=$($actual.IsPeak) (기대 $ExpectIsPeak)" }
    if ($actual.Reason -ne $ExpectReason) { $problems += "Reason=$($actual.Reason) (기대 $ExpectReason)" }
    if ($actual.Confidence -ne $ExpectConfidence) { $problems += "Confidence=$($actual.Confidence) (기대 $ExpectConfidence)" }

    if ($problems.Count -gt 0) {
        $script:Fail++
        Write-Host "FAIL $Label — $($problems -join '; ')"
        return
    }

    $script:Pass++
    Write-Host "PASS $Label"
}

function Assert-NextChange {
    param(
        [string] $Label,
        [string] $KstLocal,
        [object] $Holiday,
        [bool]   $TreatMakeupAsPeak = $true,
        [string] $ExpectKstLocal
    )

    $utc = New-KstUtc -Local $KstLocal
    $expected = New-KstUtc -Local $ExpectKstLocal
    try {
        $actual = Get-PeakNextChange -UtcNow $utc -HolidayData $Holiday -TreatMakeupAsPeak $TreatMakeupAsPeak
    }
    catch {
        $script:Fail++
        Write-Host "FAIL $Label — 예외: $($_.Exception.Message)"
        return
    }

    if ($null -ne $actual -and $actual.Kind -eq [System.DateTimeKind]::Utc -and $actual -eq $expected) {
        $script:Pass++
        Write-Host "PASS $Label"
        return
    }

    $shown = if ($null -eq $actual) { '<null>' } else { "$($actual.ToString('u')) ($($actual.Kind))" }
    $script:Fail++
    Write-Host "FAIL $Label — next=$shown (기대 $($expected.ToString('u')) UTC)"
}

$holiday2026 = New-Holiday2026
$holiday2027 = New-Holiday2027Empty

# --- 스펙 §5 표 ---
Assert-Decision -Label '#1 평일 01:00 KST = UTC 16시'        -KstLocal '2026-10-20T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekday-offpeak' -ExpectConfidence 'exact'
Assert-Decision -Label '#2 평일 11:00 KST = UTC 02시'        -KstLocal '2026-10-20T11:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'weekday-peak'     -ExpectConfidence 'exact'
Assert-Decision -Label '#3 평일 14:00 KST = UTC 05시'        -KstLocal '2026-10-20T14:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekday-offpeak' -ExpectConfidence 'exact'
Assert-Decision -Label '#4 평일 16:00 KST = UTC 07시'        -KstLocal '2026-10-20T16:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'weekday-peak'     -ExpectConfidence 'exact'
Assert-Decision -Label '#5 토요일 11:00 KST'                 -KstLocal '2026-10-24T11:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekend'         -ExpectConfidence 'exact'
Assert-Decision -Label '#6 국경절 10-01 11:00 KST'           -KstLocal '2026-10-01T11:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'holiday'         -ExpectConfidence 'exact'
Assert-Decision -Label '#7 대체근무일 10-10 11:00 KST'       -KstLocal '2026-10-10T11:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'makeup-workday'  -ExpectConfidence 'exact'
Assert-Decision -Label '#7b 대체근무일 플래그 off'           -KstLocal '2026-10-10T11:00:00+09:00' -Holiday $holiday2026 -TreatMakeupAsPeak $false -ExpectIsPeak $false -ExpectReason 'makeup-workday' -ExpectConfidence 'exact'
Assert-Decision -Label '#8 2027 미공고 01-05 11:00 KST'      -KstLocal '2027-01-05T11:00:00+09:00' -Holiday $holiday2027 -ExpectIsPeak $true  -ExpectReason 'weekday-peak' -ExpectConfidence 'estimated'
Assert-Decision -Label '#9 데이터 없음 토요일'               -KstLocal '2026-10-24T11:00:00+09:00' -Holiday $null       -ExpectIsPeak $false -ExpectReason 'weekend'         -ExpectConfidence 'estimated'

# --- 경계: UTC 피크 창 [01,04) [06,10) ---
Assert-Decision -Label '경계 KST 10:00 = UTC 01:00 시작'     -KstLocal '2026-10-20T10:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'weekday-peak'     -ExpectConfidence 'exact'
Assert-Decision -Label '경계 KST 12:59 = UTC 03:59'          -KstLocal '2026-10-20T12:59:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'weekday-peak'     -ExpectConfidence 'exact'
Assert-Decision -Label '경계 KST 13:00 = UTC 04:00 종료'     -KstLocal '2026-10-20T13:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekday-offpeak' -ExpectConfidence 'exact'
Assert-Decision -Label '경계 KST 15:00 = UTC 06:00 시작'     -KstLocal '2026-10-20T15:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'weekday-peak'     -ExpectConfidence 'exact'
Assert-Decision -Label '경계 KST 18:59 = UTC 09:59'          -KstLocal '2026-10-20T18:59:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'weekday-peak'     -ExpectConfidence 'exact'
Assert-Decision -Label '경계 KST 19:00 = UTC 10:00 종료'     -KstLocal '2026-10-20T19:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekday-offpeak' -ExpectConfidence 'exact'

# --- 베이징 달력일 경계: UTC 날짜가 아니라 UTC+8 날짜로 공휴일을 찾는다 ---
Assert-Decision -Label '국경절 시작 북경 00:00 (KST 01:00)' -KstLocal '2026-10-01T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'holiday'         -ExpectConfidence 'exact'
Assert-Decision -Label '국경절 종료 북경 00:00 (KST 01:00)' -KstLocal '2026-10-08T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekday-offpeak' -ExpectConfidence 'exact'
Assert-Decision -Label '대체근무일 시작 북경 00:00 (KST 01:00)' -KstLocal '2026-10-10T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'makeup-workday'  -ExpectConfidence 'exact'
Assert-Decision -Label '대체근무일 종료 북경 00:00 (KST 01:00)' -KstLocal '2026-10-11T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekend'         -ExpectConfidence 'exact'

# --- 베이징 달력일 경계: UTC 날짜가 아니라 UTC+8 날짜로 공휴일을 찾는다 ---
Assert-Decision -Label '국경절 시작 북경 00:00 (KST 01:00)' -KstLocal '2026-10-01T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'holiday'         -ExpectConfidence 'exact'
Assert-Decision -Label '국경절 종료 북경 00:00 (KST 01:00)' -KstLocal '2026-10-08T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekday-offpeak' -ExpectConfidence 'exact'
Assert-Decision -Label '대체근무일 시작 북경 00:00 (KST 01:00)' -KstLocal '2026-10-10T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $true  -ExpectReason 'makeup-workday'  -ExpectConfidence 'exact'
Assert-Decision -Label '대체근무일 종료 북경 00:00 (KST 01:00)' -KstLocal '2026-10-11T01:00:00+09:00' -Holiday $holiday2026 -ExpectIsPeak $false -ExpectReason 'weekend'         -ExpectConfidence 'exact'

# --- 스펙 §4.1 다음 전환 시각 ---
Assert-NextChange -Label '전환 오프피크→피크 (01:00→10:00 KST)' -KstLocal '2026-10-20T01:00:00+09:00' -Holiday $holiday2026 -ExpectKstLocal '2026-10-20T10:00:00+09:00'
Assert-NextChange -Label '전환 피크→오프피크 (11:00→13:00 KST)' -KstLocal '2026-10-20T11:00:00+09:00' -Holiday $holiday2026 -ExpectKstLocal '2026-10-20T13:00:00+09:00'
Assert-NextChange -Label '대체근무일 종일 피크 → 일요일 00:00Z'  -KstLocal '2026-10-10T11:00:00+09:00' -Holiday $holiday2026 -ExpectKstLocal '2026-10-11T01:00:00+09:00'

Write-Host ''
Write-Host "peak-decisions: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
