<#
.SYNOPSIS    BYO 폰트 로더의 저장·MOTW 제거·FontFamily 생성을 검증한다.
.DESCRIPTION 임시 폰트 루트에 digital-7.ttf를 드롭한 것처럼 복사하고 Zone.Identifier를 붙인 뒤,
             Import-NotifyFontFile이 custom-*로 저장하고 패밀리를 해석하는지 확인한다.
.CONTRACT    app\font-loader.ps1
.INPUTS      없음.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 통과.
.SIDE-EFFECTS 임시 디렉터리 생성·삭제.
.TESTS       tests\run-all.ps1
.NOTES       실제 사용자 폰트 폴더는 건드리지 않는다.
#>

#region INDEX
#   Assert-True   조건 비교
#   (main)        L1 기본 폰트, L2 드롭 저장, L3 MOTW 제거, L4 패밀리, L5 시작 로드
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'config.ps1')
. (Join-Path $repoRoot 'app\font-loader.ps1')

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-font-loader-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $default = Get-NotifyDefaultFontFamily
    Assert-True -Condition ($null -ne $default -and @($default.GetTypefaces()).Count -gt 0) -Label 'L1 기본 시스템 폰트'

    $fontRoot = Join-Path $tmp 'fonts'
    New-Item -ItemType Directory -Path $fontRoot -Force | Out-Null
    $source = Join-Path $tmp 'digital-7.ttf'
    Copy-Item -LiteralPath (Join-Path $repoRoot 'ui\assets\digital-7.ttf') -Destination $source -Force
    Set-Content -LiteralPath $source -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII

    $font = Import-NotifyFontFile -Path $source -FontRoot $fontRoot
    Assert-True -Condition (Test-Path -LiteralPath $font.Path) -Label 'L2 드롭 폰트 저장'
    Assert-True -Condition ($font.Path -like '*\custom\custom-*') -Label 'L2b 격리 custom 경로'
    Assert-True -Condition (-not (Get-Item -LiteralPath $font.Path -Stream Zone.Identifier -ErrorAction SilentlyContinue)) -Label 'L3 MOTW 제거'
    Assert-True -Condition ($font.FamilyName -eq 'Digital-7') -Label 'L4 패밀리 이름'
    Assert-True -Condition (@($font.FontFamily.GetTypefaces()).Count -gt 0) -Label 'L4b FontFamily 로드'

    $startup = Get-NotifyStartupFont -FontRoot $fontRoot
    Assert-True -Condition ($startup.FamilyName -eq 'Digital-7') -Label 'L5 시작 시 custom 폰트 로드'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "font-loader: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
