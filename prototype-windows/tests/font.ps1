<#
.SYNOPSIS    임베디드 digital-7 폰트 파일과 패밀리 이름을 검사한다.
.DESCRIPTION TTF 시그니처(00 01 00 00)와 PrivateFontCollection 으로 읽히는 패밀리 이름을 확인한다.
             카드 타이머가 이 폰트를 file:// URI 로 로드하므로 파일/이름이 곧 계약이다.
.CONTRACT    ui\indicator.ps1 — 타이머 폰트 로드
.INPUTS      없음. ui\assets\digital-7.ttf 검사.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 없음.
.TESTS       docs\2026-10-20-dsh-notify-design.md §3.1
.NOTES       digital-7 은 무료(개인용) 폰트. 재배포·상업적 사용 조건은 동봉 라이선스 참고.
#>

#region INDEX
#   Assert-Value  값 비교
#   (main)        F1 파일, F2 TTF 시그니처, F3 패밀리 이름, F4 제목 폰트 해석
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$fontPath = Join-Path $repoRoot 'ui\assets\digital-7.ttf'

$script:Pass = 0
$script:Fail = 0

function Assert-Value {
    param([object] $Actual, [object] $Expected, [string] $Label)
    if ("$Actual" -eq "$Expected") { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$Actual' (기대 '$Expected')"
}

Assert-Value -Actual (Test-Path -LiteralPath $fontPath) -Expected $true -Label 'F1 폰트 파일 존재'

$bytes = [System.IO.File]::ReadAllBytes($fontPath)[0..3]
Assert-Value -Actual (($bytes | ForEach-Object { $_.ToString('X2') }) -join ' ') -Expected '00 01 00 00' -Label 'F2 TTF 시그니처'

Add-Type -AssemblyName System.Drawing
$collection = New-Object System.Drawing.Text.PrivateFontCollection
try {
    $collection.AddFontFile($fontPath)
    $names = @($collection.Families | ForEach-Object { $_.Name })
    Assert-Value -Actual ($names -contains 'Digital-7') -Expected $true -Label "F3 패밀리 이름 ($($names -join ', '))"
}
finally {
    $collection.Dispose()
}

# F4 제목 폰트(Pretendard)는 시스템 설치본을 쓴다 — 임베드 대상은 digital-7 뿐
Add-Type -AssemblyName PresentationCore
$typeface = New-Object System.Windows.Media.Typeface(
    (New-Object System.Windows.Media.FontFamily('Pretendard')),
    [System.Windows.FontStyles]::Normal, [System.Windows.FontWeights]::Normal, [System.Windows.FontStretches]::Normal)
$glyph = $null
$resolved = $typeface.TryGetGlyphTypeface([ref]$glyph)
Assert-Value -Actual $resolved -Expected $true -Label 'F4 Pretendard 해석'
if ($resolved) {
    Assert-Value -Actual ($glyph.FontUri.LocalPath -match 'Pretendard') -Expected $true -Label "F4b 제목 폰트 파일 ($([System.IO.Path]::GetFileName($glyph.FontUri.LocalPath)))"
}

Write-Host ''
Write-Host "font: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
