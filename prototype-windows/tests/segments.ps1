<#
.SYNOPSIS    7세그먼트 타이머 렌더링용 세그먼트 맵을 검증한다.
.DESCRIPTION 문자→세그먼트 매핑은 순수 함수라 결정적으로 검사한다. 비주얼은 렌더 테스트에서 픽셀로 확인한다.
.CONTRACT    ui\segments.ps1 — Get-SevenSegmentMap
.INPUTS      없음.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 없음.
.TESTS       docs\2026-10-20-dsh-notify-design.md §3.1 (타이머)
.NOTES       7세그: a(상) b(우상) c(우하) d(하) e(좌하) f(좌상) g(중).
#>

#region INDEX
#   Assert-Set  세그먼트 집합 비교 (정렬 후 문자열)
#   (main)      S1-S5
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$segmentsPath = Join-Path $repoRoot 'ui\segments.ps1'
if (-not (Test-Path -LiteralPath $segmentsPath)) {
    Write-Host 'RED: ui\segments.ps1 이 없습니다.'
    exit 1
}
. $segmentsPath

$script:Pass = 0
$script:Fail = 0

function Assert-Set {
    param([string[]] $Actual, [string[]] $Expected, [string] $Label)
    $a = (($Actual | Sort-Object) -join '')
    $e = (($Expected | Sort-Object) -join '')
    if ($a -eq $e) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$a' (기대 '$e')"
}

Assert-Set -Actual (Get-SevenSegmentMap -Char '0') -Expected @('a','b','c','d','e','f') -Label 'S1 0 = 상우하좌 + 상하'
Assert-Set -Actual (Get-SevenSegmentMap -Char '8') -Expected @('a','b','c','d','e','f','g') -Label 'S2 8 = 전체'
Assert-Set -Actual (Get-SevenSegmentMap -Char '1') -Expected @('b','c') -Label 'S3 1 = 우측 두 세그먼트'
Assert-Set -Actual (Get-SevenSegmentMap -Char '7') -Expected @('a','b','c') -Label 'S4 7 = 상단 + 우측'
Assert-Set -Actual (Get-SevenSegmentMap -Char ':') -Expected @() -Label 'S5 콜론 = 세그먼트 없음'

$threw = $false
try { [void](Get-SevenSegmentMap -Char 'X') } catch { $threw = $true }
Assert-Set -Actual @($(if ($threw) { 'throw' } else { 'no' })) -Expected @('throw') -Label 'S6 미지 문자는 오류'

Write-Host ''
Write-Host "segments: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
