<#
.SYNOPSIS    글로벌 3개 시간대(서울·런던·뉴욕)에서 상태·카운트다운·DST 표시를 실측한다.
.DESCRIPTION 동일한 UTC 절대 시각을 각 시간대의 로컬 DateTime으로 변환한 뒤 다시 UTC로 복원해
             Get-PeakDecision/Get-PeakNextChange/Format-PeakTimer/Format-PeakSpan 결과가
             단 1초도 다르지 않은지 확인한다. 런던 BST·뉴욕 EDT/EST 전환과 베이징 자정의
             대체근무일 경계도 고정한다.
.CONTRACT    providers\deepseek-peak.ps1 — Get-PeakDecision, Get-PeakNextChange
             ui\presenter.ps1 — Format-PeakTimer, Format-PeakSpan
             config.ps1 — Format-RegionWindow
.INPUTS      없음. 네트워크·캐시 미사용(고정 공휴일 픽스처).
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 통과.
.SIDE-EFFECTS 없음.
.TESTS       docs\2026-10-23-timezone-global-report.md §4
.NOTES       OS 시간대를 바꾸지 않고 TimeZoneInfo 변환 경계를 모킹한다.
#>

#region INDEX
#   New-Utc             ISO 문자열 → UTC DateTime
#   Get-Zone            IANA 우선, Windows ID 폴백
#   Assert-True         불리언 비교
#   Assert-Equal        문자열/스칼라 비교
#   Assert-Instant      한 UTC 시각을 3개 시간대로 복원해 동일성 검증
#   (main)              T1~T5: 상태·카운트다운·DST·베이징 경계
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'providers\deepseek-peak.ps1')
. (Join-Path $repoRoot 'ui\presenter.ps1')
. (Join-Path $repoRoot 'config.ps1')

$script:Pass = 0
$script:Fail = 0

function New-Utc {
    param([string] $Iso)
    return [datetimeoffset]::Parse($Iso, [cultureinfo]::InvariantCulture).UtcDateTime
}

function Get-Zone {
    param([string] $Iana, [string] $Windows)
    try { return [System.TimeZoneInfo]::FindSystemTimeZoneById($Iana) }
    catch {
        try { return [System.TimeZoneInfo]::FindSystemTimeZoneById($Windows) }
        catch { throw "시간대를 찾을 수 없습니다: $Iana / $Windows" }
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

function Assert-Equal {
    param([object] $Actual, [object] $Expected, [string] $Label)
    if ("$Actual" -eq "$Expected") { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$Actual' (기대 '$Expected')"
}

function New-Holiday2026 {
    $days = [System.Collections.Generic.List[object]]::new()
    foreach ($d in 1..7) {
        $days.Add([pscustomobject]@{ name = '国庆节'; date = ('2026-10-{0:00}' -f $d); isOffDay = $true })
    }
    $days.Add([pscustomobject]@{ name = '国庆节'; date = '2026-10-10'; isOffDay = $false })
    return [pscustomobject]@{
        year   = 2026
        papers = @('https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm')
        days   = $days.ToArray()
    }
}

$holiday = New-Holiday2026
$seoul = Get-Zone -Iana 'Asia/Seoul' -Windows 'Korea Standard Time'
$london = Get-Zone -Iana 'Europe/London' -Windows 'GMT Standard Time'
$newYork = Get-Zone -Iana 'America/New_York' -Windows 'Eastern Standard Time'
$cases = @(
    [pscustomobject]@{ Name = 'Seoul'; Zone = $seoul },
    [pscustomobject]@{ Name = 'London'; Zone = $london },
    [pscustomobject]@{ Name = 'NewYork'; Zone = $newYork }
)

function Assert-Instant {
    param([string] $Iso, [string] $Label)

    $utc = New-Utc -Iso $Iso
    $decision = Get-PeakDecision -UtcNow $utc -HolidayData $holiday
    $next = Get-PeakNextChange -UtcNow $utc -HolidayData $holiday
    $timer = Format-PeakTimer -NextChangeAt $next -Now $utc
    $span = Format-PeakSpan -NextChangeAt $next -UtcNow $utc
    $nextTicks = if ($null -eq $next) { 0 } else { ([datetime]$next).ToUniversalTime().Ticks }

    $mismatch = @()
    foreach ($case in $cases) {
        $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $case.Zone)
        $offset = $case.Zone.GetUtcOffset($utc)
        $restored = ([datetimeoffset]::new($local, $offset)).UtcDateTime
        if ($restored.Ticks -ne $utc.Ticks) { $mismatch += "$($case.Name):restore" }

        $caseDecision = Get-PeakDecision -UtcNow $restored -HolidayData $holiday
        $caseNext = Get-PeakNextChange -UtcNow $restored -HolidayData $holiday
        $caseTimer = Format-PeakTimer -NextChangeAt $caseNext -Now $restored
        $caseSpan = Format-PeakSpan -NextChangeAt $caseNext -UtcNow $restored
        $caseTicks = if ($null -eq $caseNext) { 0 } else { ([datetime]$caseNext).ToUniversalTime().Ticks }

        if ($caseDecision.IsPeak -ne $decision.IsPeak) { $mismatch += "$($case.Name):IsPeak" }
        if ($caseTicks -ne $nextTicks) { $mismatch += "$($case.Name):next" }
        if ($caseTimer -ne $timer) { $mismatch += "$($case.Name):timer" }
        if ($caseSpan -ne $span) { $mismatch += "$($case.Name):span" }
    }

    Assert-True -Condition ($mismatch.Count -eq 0) -Label "$Label — 3개 시간대 동일 (peak=$($decision.IsPeak), next=$($next.ToString('u')), timer=$timer, span=$span)"
}

# T1: 국경절 오프피크 + 베이징 자정 진입/이탈
Assert-Instant -Iso '2026-09-30T15:59:59Z' -Label 'T1a 국경절 1초 전'
Assert-Instant -Iso '2026-09-30T16:00:00Z' -Label 'T1b 국경절 시작(베이징 00:00)'
Assert-Instant -Iso '2026-10-01T01:00:00Z' -Label 'T1c 국경절 피크창(오프피크)'
Assert-Instant -Iso '2026-10-07T15:59:59Z' -Label 'T1d 국경절 마지막 1초'
Assert-Instant -Iso '2026-10-07T16:00:00Z' -Label 'T1e 국경절 종료(베이징 00:00)'
Assert-Instant -Iso '2026-10-08T00:59:59Z' -Label 'T1f 국경절 후 피크 1초 전'
Assert-Instant -Iso '2026-10-08T01:00:00Z' -Label 'T1g 국경절 후 피크 시작'

# T2: 일일 피크 진입/이탈 (UTC 01:00/04:00/06:00/10:00)
Assert-Instant -Iso '2026-10-20T00:59:59Z' -Label 'T2a 일일 피크 1초 전'
Assert-Instant -Iso '2026-10-20T01:00:00Z' -Label 'T2b 일일 피크 시작'
Assert-Instant -Iso '2026-10-20T03:59:59Z' -Label 'T2c 오전 피크 마지막 1초'
Assert-Instant -Iso '2026-10-20T04:00:00Z' -Label 'T2d 오전 피크 종료'
Assert-Instant -Iso '2026-10-20T06:00:00Z' -Label 'T2e 오후 피크 시작'
Assert-Instant -Iso '2026-10-20T09:59:59Z' -Label 'T2f 오후 피크 마지막 1초'
Assert-Instant -Iso '2026-10-20T10:00:00Z' -Label 'T2g 오후 피크 종료'

# T3: 대체근무일(调休) 베이징 자정 경계 — UTC 날짜가 아니라 UTC+8 날짜
Assert-Instant -Iso '2026-10-09T15:59:59Z' -Label 'T3a 대체근무일 1초 전'
Assert-Instant -Iso '2026-10-09T16:00:00Z' -Label 'T3b 대체근무일 시작(베이징 00:00)'
Assert-Instant -Iso '2026-10-10T15:59:59Z' -Label 'T3c 대체근무일 마지막 1초'
Assert-Instant -Iso '2026-10-10T16:00:00Z' -Label 'T3d 대체근무일 종료(베이징 00:00)'

# T4: DST 전환 — 런던 BST 시작/종료, 뉴욕 EDT/EST
$dstCases = @(
    @{ Iso = '2026-01-15T12:00:00Z'; London = 0;  NewYork = -5; Seoul = 9 },
    @{ Iso = '2026-03-29T00:59:59Z'; London = 0;  NewYork = -4; Seoul = 9 },
    @{ Iso = '2026-03-29T01:00:00Z'; London = 1;  NewYork = -4; Seoul = 9 },
    @{ Iso = '2026-07-15T12:00:00Z'; London = 1;  NewYork = -4; Seoul = 9 },
    @{ Iso = '2026-10-25T00:59:59Z'; London = 1;  NewYork = -4; Seoul = 9 },
    @{ Iso = '2026-10-25T01:00:00Z'; London = 0;  NewYork = -4; Seoul = 9 },
    @{ Iso = '2026-11-01T05:59:59Z'; London = 0;  NewYork = -4; Seoul = 9 },
    @{ Iso = '2026-11-01T06:00:00Z'; London = 0;  NewYork = -5; Seoul = 9 }
)
foreach ($case in $dstCases) {
    $utc = New-Utc -Iso $case.Iso
    Assert-Equal -Actual $london.GetUtcOffset($utc).TotalHours -Expected $case.London -Label "T4 런던 offset $($case.Iso)"
    Assert-Equal -Actual $newYork.GetUtcOffset($utc).TotalHours -Expected $case.NewYork -Label "T4 뉴욕 offset $($case.Iso)"
    Assert-Equal -Actual $seoul.GetUtcOffset($utc).TotalHours -Expected $case.Seoul -Label "T4 서울 offset $($case.Iso)"
}

# T5: 시간대 표기 (수동 가감이 아니라 TimeZoneInfo 사용)
$utc = New-Utc -Iso '2026-07-15T12:00:00Z'
$next = $utc.AddHours(2)
$londonText = Format-RegionWindow -UtcNow $utc -NextChangeAt $next -TimeZone $london
$newYorkText = Format-RegionWindow -UtcNow $utc -NextChangeAt $next -TimeZone $newYork
Assert-True -Condition ($londonText -match 'UTC\+1') -Label "T5 런던 BST 표기 ($londonText)"
Assert-True -Condition ($newYorkText -match 'UTC-4') -Label "T5 뉴욕 EDT 표기 ($newYorkText)"

Write-Host ''
Write-Host "timezone-matrix: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
