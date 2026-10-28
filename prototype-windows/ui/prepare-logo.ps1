<#
.SYNOPSIS    로고 소스(워드마크 포함)에서 심볼만 잘라 트레이용 마스터 PNG 를 만든다.
.DESCRIPTION ui\assets\deepseek-logo-source.png → ui\assets\deepseek-logo.png (정사각, 투명 배경).
             이후 ui\build-icons.ps1 이 이 마스터에서 4색 ICO 를 만든다.
.CONTRACT    ui\logo.ps1 — Get-LogoGlyph
.INPUTS      -Source(기본 assets 원본), -Out(기본 assets 마스터), -MarginRatio
.OUTPUTS     deepseek-logo.png, 콘솔에 결과 크기
.SIDE-EFFECTS 마스터 PNG 덮어쓰기.
.TESTS       tests\logo-mask.ps1 L1-L3
.NOTES       원본은 DeepSeek 상표. 로컬 트레이 표시 용도로만 사용한다.
#>

#region INDEX
#   (main)  소스 확인 → 심볼 크롭 → 마스터 저장
#endregion

param(
    [string] $Source = (Join-Path $PSScriptRoot 'assets\deepseek-logo-source.png'),
    [string] $Out = (Join-Path $PSScriptRoot 'assets\deepseek-logo.png'),
    [double] $MarginRatio = 0.05
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'logo.ps1')

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Host "FAIL: 소스 로고 없음 — $Source"
    exit 1
}

$bitmap = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $Source).Path)
try {
    $glyph = Get-LogoGlyph -Source $bitmap -MarginRatio $MarginRatio
    try {
        $glyph.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "OK: glyph $($glyph.Width)x$($glyph.Height) -> $Out"
    }
    finally { $glyph.Dispose() }
}
finally { $bitmap.Dispose() }

exit 0
