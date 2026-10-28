<#
.SYNOPSIS    세션 시작 시 피크 경고 토스트(peak-alert)의 메시지 선택과 dry-run 출력을 검증한다.
.DESCRIPTION 고정 시각과 네트워크 차단(-NoFetch)으로 피크/오프피크를 결정적으로 만들고,
             피크일 때만 XML 이 나오는지, -Force 가 오프피크에서도 표시하는지 확인한다.
.CONTRACT    notify\peak-alert.ps1 — Get-PeakAlertMessage, CLI
.INPUTS      없음. CLI 를 자식 프로세스로 호출한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 임시 캐시 디렉터리 생성·삭제. 실제 토스트는 띄우지 않는다(-DryRun).
.TESTS       docs\dsh-harness-notify-spec.md §8 (세션 시작 피크 알림)
.NOTES       피크 여부는 providers\deepseek-peak.ps1 의 판정을 그대로 쓴다.
#>

#region INDEX
#   New-TempCache   공휴일 데이터 없는 임시 캐시
#   Invoke-Alert    peak-alert.ps1 dry-run 호출
#   (main)          A 피크 / B 오프피크 침묵 / C -Force / D 본문 구성
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $repoRoot 'notify\peak-alert.ps1'

if (-not (Test-Path -LiteralPath $cliPath)) {
    Write-Host 'RED: notify\peak-alert.ps1 이 없습니다.'
    exit 1
}

$script:Pass = 0
$script:Fail = 0

function New-TempCache {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-peak-alert-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Invoke-Alert {
    param([string] $Now, [switch] $Force)

    $cacheDir = New-TempCache
    try {
        $cliArgs = @('-NoProfile', '-NoLogo', '-File', $cliPath, '-Now', $Now, '-CacheDir', $cacheDir, '-NoFetch', '-DryRun')
        if ($Force) { $cliArgs += '-Force' }
        $out = & pwsh @cliArgs 2>&1
        return [pscustomobject]@{ Output = ($out -join "`n"); ExitCode = $LASTEXITCODE }
    }
    finally {
        Remove-Item -LiteralPath $cacheDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

# A 피크 → 경고 토스트
$r = Invoke-Alert -Now '2026-10-20T11:00:00+09:00'
Assert-True -Condition ($r.ExitCode -eq 0 -and $r.Output.Contains('지금 PEAK · 100%')) -Label 'A1 피크 → 제목'
Assert-True -Condition ($r.Output.Contains('피크')) -Label 'A2 피크 → 본문 안내'

# B 오프피크 → 침묵
$r = Invoke-Alert -Now '2026-10-20T14:00:00+09:00'
Assert-True -Condition ($r.ExitCode -eq 0 -and -not $r.Output.Contains('<toast')) -Label 'B 오프피크 → 출력 없음'

# C -Force 는 오프피크에서도 표시
$r = Invoke-Alert -Now '2026-10-20T14:00:00+09:00' -Force
Assert-True -Condition ($r.Output.Contains('OFF-PEAK · 50%')) -Label 'C -Force → 오프피크 표시'

# D 본문에 다음 전환 시간이 붙는다
$r = Invoke-Alert -Now '2026-10-20T11:00:00+09:00'
Assert-True -Condition ($r.Output.Contains('→ 다음 구간까지 2h 00m')) -Label 'D 본문에 다음 전환 시간'

Write-Host ''
Write-Host "peak-alert: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
