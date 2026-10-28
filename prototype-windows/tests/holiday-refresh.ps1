<#
.SYNOPSIS    공휴일 캐시 갱신 판단(동기/비동기/건너뜀) 규칙을 검증한다.
.DESCRIPTION 10일 TTL, 실행 중인 갱신 작업, 실패 쿨다운을 조합한 순수 판단 함수를 검사한다.
             네트워크·시계 의존이 없도록 모든 입력을 인자로 주입한다.
.CONTRACT    providers\deepseek-peak.ps1 — Get-HolidayRefreshPlan
.INPUTS      없음. providers\deepseek-peak.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 없음.
.TESTS       docs\deepseek-peak-spec.md §2.5 (캐시 정책·비동기 갱신)
.NOTES       'sync' = 첫 실행(캐시 없음), 'async' = 백그라운드 갱신, 'skip' = 캐시 사용.
#>

#region INDEX
#   Assert-Value   스칼라 기대값 비교
#   (main)         판단 규칙 R1-R9
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

function Assert-Value {
    param([object] $Actual, [object] $Expected, [string] $Label)

    if ("$Actual" -eq "$Expected") { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$Actual' (기대 '$Expected')"
}

# R1 TTL 이내 → 재사용
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 240 -AgeHours 1 -HasCache) -Expected 'skip' -Label 'R1 10일 TTL 이내 → skip'

# R2 TTL 초과 → 비동기 갱신
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 240 -AgeHours 241 -HasCache) -Expected 'async' -Label 'R2 TTL 초과 → async'

# R3 이미 갱신 중 → 중복 실행 금지
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 240 -AgeHours 241 -HasCache -JobRunning) -Expected 'skip' -Label 'R3 갱신 실행 중 → skip'

# R4 실패 쿨다운(1시간) 이내 → 재시도 금지
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 240 -AgeHours 241 -HasCache -LastAttemptHoursAgo 0.5) -Expected 'skip' -Label 'R4 쿨다운 이내 → skip'

# R5 쿨다운 경과 → 재시도
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 240 -AgeHours 241 -HasCache -LastAttemptHoursAgo 2) -Expected 'async' -Label 'R5 쿨다운 경과 → async'

# R6 캐시 없음(첫 실행) → 동기
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 240 -AgeHours 0 -HasCache:$false) -Expected 'sync' -Label 'R6 첫 실행 → sync'

# R7 TTL 경계: 나이 == TTL → 만료
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 240 -AgeHours 240 -HasCache) -Expected 'async' -Label 'R7 경계(age=TTL) → async'

# R8 TTL 0 = 항상 만료
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 0 -AgeHours 0.01 -HasCache) -Expected 'async' -Label 'R8 TTL 0 → async'

# R9 캐시 없음 + 갱신 중 → 동기 우선 (첫 실행은 기다린다)
Assert-Value -Actual (Get-HolidayRefreshPlan -TtlHours 240 -AgeHours 0 -HasCache:$false -JobRunning) -Expected 'sync' -Label 'R9 첫 실행 + 실행 중 → sync'

Write-Host ''
Write-Host "holiday-refresh: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
