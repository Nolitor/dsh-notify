<#
.SYNOPSIS    provider 설정 기본값과 공휴일 캐시 TTL 규칙을 검증한다.
.DESCRIPTION config 가 비어 있을 때의 기본값(대체근무일=피크, 갱신 주기=10일)과,
             미공고 데이터(papers 비어 있음)일 때의 TTL 단축 규칙을 확인한다.
             순수 함수만 검사하므로 네트워크·시각 의존이 없다.
.CONTRACT    providers\deepseek-peak.ps1 — Get-PeakConfig, Get-HolidayCacheTtl
.INPUTS      없음. providers\deepseek-peak.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 없음.
.TESTS       docs\deepseek-peak-spec.md §2.5 (캐시 정책), §6 (설정 섹션)
.NOTES       TTL 단축의 목적: 연도 초에 미공고 파일이 TTL 단위로 묵는 것을 막는다.
#>

#region INDEX
#   Assert-Value   속성/스칼라 기대값 비교
#   (main)         설정 기본값 C0-C1, TTL 규칙 T1-T5
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

# --- 설정 기본값 ---
$default = Get-PeakConfig -Config @{}
Assert-Value -Actual $default.TreatMakeupAsPeak -Expected $true -Label 'C0 기본 treatMakeupAsPeak = true'
Assert-Value -Actual $default.RefreshHours -Expected 240 -Label 'C0 기본 refreshHours = 240 (10일)'

$override = Get-PeakConfig -Config @{ treatMakeupAsPeak = $false; refreshHours = 24 }
Assert-Value -Actual $override.TreatMakeupAsPeak -Expected $false -Label 'C1 설정 override treatMakeupAsPeak'
Assert-Value -Actual $override.RefreshHours -Expected 24 -Label 'C1 설정 override refreshHours'

# --- 캐시 TTL ---
$announced = [pscustomobject]@{ papers = @('https://example.invalid/p.htm'); days = @() }
$unannounced = [pscustomobject]@{ papers = @(); days = @() }

Assert-Value -Actual (Get-HolidayCacheTtl -RefreshHours 240 -Data $announced) -Expected 240 -Label 'T1 공고 완료 → 설정 TTL 그대로'
Assert-Value -Actual (Get-HolidayCacheTtl -RefreshHours 240 -Data $unannounced) -Expected 24 -Label 'T2 미공고 → TTL 24h 로 단축'
Assert-Value -Actual (Get-HolidayCacheTtl -RefreshHours 6 -Data $unannounced) -Expected 6 -Label 'T3 미공고 + 짧은 TTL → 그대로 6'
Assert-Value -Actual (Get-HolidayCacheTtl -RefreshHours 0 -Data $announced) -Expected 0 -Label 'T4 TTL 0 유지 (항상 만료)'
Assert-Value -Actual (Get-HolidayCacheTtl -RefreshHours 240 -Data $null) -Expected 240 -Label 'T5 데이터 없음 → 설정 TTL'

Write-Host ''
Write-Host "provider-config: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
