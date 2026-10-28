<#
.SYNOPSIS    인디케이터 카드를 오프스크린 렌더해 색·크기·중앙 정렬을 검증한다.
.DESCRIPTION 제목은 DeepSeek CI 블루, 타이머 본문은 피크=소프트 레드 / 오프피크=그린,
             초(SS)는 배경에 가까운 회색으로 죽인다. 타이머 전체(본문+초)가 카드 중앙에 오는지 확인한다.
.CONTRACT    ui\render-indicator.ps1, ui\indicator.ps1
.INPUTS      없음.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 임시 디렉터리 생성·삭제.
.TESTS       docs\2026-10-20-dsh-notify-design.md §3.1
.NOTES       카드 210x92 @2x + 20px 여백 = 460x224. 카드 중심 (230, 112).
#>

#region INDEX
#   Invoke-Render    STA 자식 프로세스로 렌더 실행
#   Get-ColorBounds  조건에 맞는 픽셀 바운딩박스
#   Assert-True      조건 비교
#   (main)           R1 크기, R2 제목 블루, R3-R6 타이머(색·중앙·초), R7 배경, R8 오프피크
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$renderPath = Join-Path $repoRoot 'ui\render-indicator.ps1'
$indicatorPath = Join-Path $repoRoot 'ui\indicator.ps1'
if (-not (Test-Path -LiteralPath $renderPath) -or -not (Test-Path -LiteralPath $indicatorPath)) {
    Write-Host 'RED: ui\indicator.ps1 또는 ui\render-indicator.ps1 이 없습니다.'
    exit 1
}

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

function Invoke-Render {
    param([string] $Severity, [string] $Out)
    $output = & pwsh -Sta -NoProfile -NoLogo -File $renderPath -Severity $Severity -Out $Out 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join ' ') }
}

function Get-ColorBounds {
    param([System.Drawing.Bitmap] $Image, [scriptblock] $Match, [int] $Top = 20, [int] $Bottom = 204)

    $minX = 9999; $maxX = -1; $minY = 9999; $maxY = -1; $count = 0
    for ($y = $Top; $y -lt $Bottom; $y++) {
        for ($x = 20; $x -lt 440; $x++) {
            if (-not (& $Match $Image.GetPixel($x, $y))) { continue }
            $count++
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
    return [pscustomobject]@{ Count = $count; MinX = $minX; MaxX = $maxX; MinY = $minY; MaxY = $maxY }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-indicator-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Add-Type -AssemblyName System.Drawing

try {
    $alertPath = Join-Path $tmp 'alert.png'
    $r = Invoke-Render -Severity 'alert' -Out $alertPath
    Assert-True -Condition ($r.ExitCode -eq 0 -and (Test-Path $alertPath)) -Label 'R1 피크 렌더 성공'

    $img = [System.Drawing.Bitmap]::FromFile($alertPath)
    try {
        Assert-True -Condition ($img.Width -eq 460 -and $img.Height -eq 224) -Label 'R1b 렌더 크기 460x224'

        $title = Get-ColorBounds -Image $img -Match { param($p) $p.B -gt 190 -and ($p.B - $p.R) -gt 60 -and ($p.B - $p.G) -gt 40 } -Bottom 64
        Assert-True -Condition ($title.Count -gt 20) -Label "R2 제목이 CI 블루 (표본 $($title.Count))"

        $red = Get-ColorBounds -Image $img -Match { param($p) $p.R -ge 190 -and $p.G -le 130 -and $p.B -le 130 }
        Assert-True -Condition ($red.Count -gt 100) -Label "R3 피크 타이머 소프트 레드 (표본 $($red.Count))"

        # 타이머 전체(본문+초)는 밴드 안의 비배경 픽셀 합으로 중앙 판정
        $minX = 9999; $maxX = -1; $minY = 9999; $maxY = -1; $dim = 0
        for ($y = 64; $y -lt 162; $y++) {
            for ($x = 20; $x -lt 440; $x++) {
                $p = $img.GetPixel($x, $y)
                if (($p.R + $p.G + $p.B) -gt 100) {
                    if ($x -lt $minX) { $minX = $x }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($y -gt $maxY) { $maxY = $y }
                }
                if ([Math]::Abs($p.R - 44) -le 10 -and [Math]::Abs($p.G - 44) -le 10 -and [Math]::Abs($p.B - 44) -le 10) { $dim++ }
            }
        }
        $centerX = ($minX + $maxX) / 2
        $centerY = ($minY + $maxY) / 2
        Assert-True -Condition ($maxX -gt $minX -and [Math]::Abs($centerX - 230) -le 12) -Label "R4 타이머 전체 가로 중앙 (x=$centerX)"
        Assert-True -Condition ([Math]::Abs($centerY - 112) -le 16) -Label "R5 타이머 세로 중앙 (y=$centerY)"
        Assert-True -Condition ($dim -gt 20) -Label "R6 초(SS)는 배경색 회색으로 죽임 (표본 $dim)"

        $dark = $img.GetPixel(400, 190)
        Assert-True -Condition ($dark.R -lt 70 -and $dark.G -lt 70 -and $dark.B -lt 70) -Label "R7 카드 배경 어두움 (R$($dark.R) G$($dark.G) B$($dark.B))"
    }
    finally { $img.Dispose() }

    $okPath = Join-Path $tmp 'ok.png'
    $r = Invoke-Render -Severity 'ok' -Out $okPath
    $img = [System.Drawing.Bitmap]::FromFile($okPath)
    try {
        $green = Get-ColorBounds -Image $img -Match { param($p) $p.G -ge 170 -and $p.R -le 130 -and $p.B -le 170 }
        Assert-True -Condition ($green.Count -gt 100) -Label "R8 오프피크 타이머 그린 (표본 $($green.Count))"
    }
    finally { $img.Dispose() }

    $a = [System.IO.File]::ReadAllBytes($alertPath)
    $b = [System.IO.File]::ReadAllBytes($okPath)
    Assert-True -Condition ($a.Length -ne $b.Length -or (Compare-Object $a $b | Measure-Object).Count -gt 0) -Label 'R9 상태별 렌더 차이'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "indicator-render: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
