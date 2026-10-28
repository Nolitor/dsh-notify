<#
.SYNOPSIS    트레이 아이콘 생성(색 입히기·크기 변환·ICO 패킹)을 검증한다.
.DESCRIPTION 합성 비트맵으로 틴트·알파 보존을 검사하고, ICO 컨테이너 헤더를 파싱해
             크기·오프셋·PNG 시그니처를 확인한다. 마지막으로 실제 로고로 4색 아이콘을 만들어
             산출물이 생성되는지 확인한다.
.CONTRACT    ui\icons.ps1 — New-TintedBitmap, Resize-Bitmap, Write-IcoFile, Build-NotifyIcons
.INPUTS      없음. ui\icons.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 임시 디렉터리 생성·삭제.
.TESTS       docs\2026-10-20-dsh-notify-design.md §3.2 (트레이 아이콘)
.NOTES       ICO 는 PNG-in-ICO(Vista+) 형식. 256px 은 폭/높이 바이트 0 으로 표기한다.
#>

#region INDEX
#   New-TempDir  임시 작업 디렉터리
#   Assert-True  조건 비교
#   (main)       T1 틴트, T2 리사이즈, T3 ICO 헤더, T4 실제 로고 4색 생성
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$iconsPath = Join-Path $repoRoot 'ui\icons.ps1'
$logoPath = Join-Path $repoRoot 'ui\assets\deepseek-logo.png'

if (-not (Test-Path -LiteralPath $iconsPath)) {
    Write-Host 'RED: ui\icons.ps1 이 없습니다.'
    exit 1
}
. $iconsPath

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

function New-TempDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-icons-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

$tmp = New-TempDir
try {
    # T1 틴트: 색 교체 + 알파 보존
    $src = New-Object System.Drawing.Bitmap 8, 8
    $src.SetPixel(0, 0, [System.Drawing.Color]::FromArgb(255, 10, 20, 30))
    $src.SetPixel(1, 0, [System.Drawing.Color]::FromArgb(128, 10, 20, 30))
    $green = [System.Drawing.Color]::FromArgb(255, 0x1E, 0x7B, 0x3C)
    $tinted = New-TintedBitmap -Source $src -Color $green
    $p0 = $tinted.GetPixel(0, 0)
    $p1 = $tinted.GetPixel(1, 0)
    $p2 = $tinted.GetPixel(7, 7)
    Assert-True -Condition ($p0.R -eq 0x1E -and $p0.G -eq 0x7B -and $p0.B -eq 0x3C -and $p0.A -eq 255) -Label 'T1 틴트 색·알파'
    Assert-True -Condition ($p1.A -eq 128) -Label 'T1b 반투명 알파 보존'
    Assert-True -Condition ($p2.A -eq 0) -Label 'T1c 투명 픽셀 유지'

    # T1d 외곽 확장: 이웃 1px 이 DilateAlpha 로 채워지고 먼 픽셀은 비어 있음
    $dot = New-Object System.Drawing.Bitmap 8, 8
    $dot.SetPixel(3, 3, [System.Drawing.Color]::FromArgb(255, 255, 255, 255))
    $dilated = New-TintedBitmap -Source $dot -Color $green -Dilate -DilateAlpha 190
    Assert-True -Condition ($dilated.GetPixel(2, 3).A -eq 190 -and $dilated.GetPixel(4, 2).A -eq 190) -Label 'T1d 외곽 1px 확장'
    Assert-True -Condition ($dilated.GetPixel(6, 6).A -eq 0) -Label 'T1e 먼 픽셀은 비어 있음'

    # T2 리사이즈: 치수 유지 + 알파 유지
    $small = Resize-Bitmap -Source $tinted -Width 16 -Height 16
    Assert-True -Condition ($small.Width -eq 16 -and $small.Height -eq 16) -Label 'T2 리사이즈 치수'
    Assert-True -Condition ($small.PixelFormat.ToString() -like '*32bppArgb*') -Label 'T2b 32bpp ARGB 유지'

    # T3 ICO 컨테이너: 2프레임, 16/32, PNG 시그니처
    $p16 = Join-Path $tmp '16.png'; $p32 = Join-Path $tmp '32.png'
    $small.Save($p16, [System.Drawing.Imaging.ImageFormat]::Png)
    $medium = Resize-Bitmap -Source $tinted -Width 32 -Height 32
    $medium.Save($p32, [System.Drawing.Imaging.ImageFormat]::Png)
    $ico = Join-Path $tmp 'test.ico'
    Write-IcoFile -PngPaths @($p16, $p32) -Sizes @(16, 32) -Path $ico

    $bytes = [System.IO.File]::ReadAllBytes($ico)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    $w0 = $bytes[6]; $h0 = $bytes[7]
    $bpp0 = [BitConverter]::ToUInt16($bytes, 12)
    $len0 = [BitConverter]::ToUInt32($bytes, 14)
    $off0 = [BitConverter]::ToUInt32($bytes, 18)
    $pngMagic = ($bytes[$off0..($off0 + 7)] | ForEach-Object { $_.ToString('X2') }) -join ''
    Assert-True -Condition ($count -eq 2) -Label 'T3 ICO 프레임 수 2'
    Assert-True -Condition ($w0 -eq 16 -and $h0 -eq 16 -and $bpp0 -eq 32) -Label 'T3b 첫 프레임 16x16x32'
    Assert-True -Condition ($len0 -gt 0 -and ($off0 + $len0) -le $bytes.Length) -Label 'T3c 오프셋 범위'
    Assert-True -Condition ($pngMagic -eq '89504E470D0A1A0A') -Label 'T3d PNG-in-ICO 시그니처'

    # T4 실제 로고로 2색(ok/alert) 생성
    $outDir = Join-Path $tmp 'out'
    Build-NotifyIcons -SourcePath $logoPath -OutDir $outDir
    $icos = @(Get-ChildItem $outDir -Filter '*.ico' -File)
    Assert-True -Condition ($icos.Count -eq 2) -Label 'T4 2색 ICO 생성 (ok/alert)'
    Assert-True -Condition (@($icos | Where-Object { $_.Length -lt 500 }).Count -eq 0) -Label 'T4b ICO 크기 타당'
    Assert-True -Condition (Test-Path (Join-Path $outDir 'preview.png')) -Label 'T4c 미리보기 생성'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "icons: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
