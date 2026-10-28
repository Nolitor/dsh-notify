<#
.SYNOPSIS    로고 소스에서 글자(wordmark)를 제외한 심볼만 잘라 정사각 마스크로 만드는지 검증한다.
.DESCRIPTION 투명 배경 + 두 덩어리(큰 심볼, 작은 글자)를 가진 합성 이미지로
             연결요소 선택·바운딩박스·정사각 패딩을 확인한다. 실제 소스가 있으면 크기도 확인한다.
.CONTRACT    ui\logo.ps1 — Get-InkComponentBounds, Get-LogoGlyph
.INPUTS      없음. ui\logo.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 임시 비트맵만 사용 (파일 없음).
.TESTS       docs\2026-10-20-dsh-notify-design.md §3.2 (아이콘 자산)
.NOTES       소스는 투명 배경 PNG. 글자와 심볼이 떨어져 있으므로 최대 연결요소가 심볼이다.
#>

#region INDEX
#   New-SyntheticLogo  큰 심볼 + 작은 글자 덩어리 합성
#   Assert-True        조건 비교
#   (main)             L1 최대 요소 선택, L2 정사각 패딩, L3 실제 소스
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$logoPath = Join-Path $repoRoot 'ui\logo.ps1'
$realSource = Join-Path $repoRoot 'ui\assets\deepseek-logo-source.png'

if (-not (Test-Path -LiteralPath $logoPath)) {
    Write-Host 'RED: ui\logo.ps1 이 없습니다.'
    exit 1
}
. $logoPath

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

# L1: 큰 덩어리(L자) 선택 + 바운딩박스 안의 다른 요소(점)는 라벨이 달라 제외
$synthetic = New-Object System.Drawing.Bitmap 60, 30
$blue = [System.Drawing.Color]::FromArgb(255, 77, 107, 254)
for ($y = 4; $y -le 26; $y++) { for ($x = 4; $x -le 9; $x++) { $synthetic.SetPixel($x, $y, $blue) } }
for ($y = 20; $y -le 26; $y++) { for ($x = 10; $x -le 20; $x++) { $synthetic.SetPixel($x, $y, $blue) } }
$synthetic.SetPixel(16, 8, $blue)   # bbox 내부의 고립된 점 (별도 컴포넌트)

$bounds = Get-InkComponentBounds -Bitmap $synthetic
Assert-True -Condition ($bounds.X -eq 4 -and $bounds.Y -eq 4 -and $bounds.Width -eq 17 -and $bounds.Height -eq 23) -Label 'L1 최대 연결요소 바운딩박스'
Assert-True -Condition ($bounds.Area -eq 215) -Label 'L1b 면적 일치 (고립점 제외)'

# L2: 정사각 패딩 + 바운딩박스 내부의 고립 요소 제거
$glyph = Get-LogoGlyph -Source $synthetic -MarginRatio 0.1
Assert-True -Condition ($glyph.Width -eq $glyph.Height) -Label 'L2 정사각 캔버스'
Assert-True -Condition ($glyph.Width -eq 28) -Label 'L2b 여백 포함 크기 (23 * 1.2 = 28)'
Assert-True -Condition ($glyph.GetPixel(0, 0).A -eq 0 -and $glyph.GetPixel($glyph.Width - 1, $glyph.Height - 1).A -eq 0) -Label 'L2c 모서리 투명'
Assert-True -Condition ($glyph.GetPixel(6, 3).A -gt 0) -Label 'L2d 심볼 픽셀 존재'
# 소스 (16,8) → 캔버스 (5+12, 2+4)
Assert-True -Condition ($glyph.GetPixel(17, 6).A -eq 0) -Label 'L2e 바운딩박스 안 고립 요소 제거'

# L3: 실제 소스가 있으면 심볼만 잘려 정사각이 되는지
if (Test-Path -LiteralPath $realSource) {
    $real = [System.Drawing.Bitmap]::FromFile($realSource)
    try {
        $glyph = Get-LogoGlyph -Source $real -MarginRatio 0.05
        Assert-True -Condition ($glyph.Width -eq $glyph.Height -and $glyph.Width -ge 150) -Label 'L3 실제 소스 정사각 마스크'
    }
    finally { $real.Dispose(); if ($glyph) { $glyph.Dispose() } }
}
else {
    Write-Host 'SKIP L3 실제 소스 없음'
}

$synthetic.Dispose()
Write-Host ''
Write-Host "logo-mask: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
