<#
.SYNOPSIS    포터블 패키지 산출물의 구성과 금지 에셋 제외를 검증한다.
.DESCRIPTION build\build-portable.ps1을 임시 출력 폴더에서 실행하고, start.cmd/app 모듈/
             중립 아이콘 포함과 Digital-7/DeepSeek 로고/ding.wav/exe/vbs 제외를 확인한다.
.CONTRACT    build\build-portable.ps1
.INPUTS      없음.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 통과.
.SIDE-EFFECTS 임시 dist 생성·삭제.
.TESTS       tests\run-all.ps1
.NOTES       실제 dist 폴더는 건드리지 않는다.
#>

#region INDEX
#   Assert-True   조건 비교
#   (main)        P1 빌드, P2 필수 파일, P3 금지 에셋, P4 start.cmd, P5 zip/hash
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-portable-' + [guid]::NewGuid().ToString('N'))
$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

try {
    $output = & pwsh -NoProfile -NoLogo -File (Join-Path $repoRoot 'build\build-portable.ps1') -Version 'test' -OutRoot $tmp 2>&1
    $package = Join-Path $tmp 'DSH-Notify-Portable'
    Assert-True -Condition ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $package)) -Label 'P1 패키지 빌드'

    foreach ($relative in @('launch.js', 'start.cmd', 'core.ps1', 'config.ps1', 'app\font-loader.ps1', 'app\tray.ps1', 'ui\icons\neutral-green.ico', 'ui\icons\neutral-red.ico', 'LICENSE', 'README.txt')) {
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $package $relative)) -Label "P2 $relative"
    }

    $forbidden = Get-ChildItem -LiteralPath $package -Recurse -File | Where-Object {
        $_.Name -match 'digital-7|deepseek-logo|deepseek-.*\.ico|ding\.wav|DSH-Notify\.exe|start\.vbs'
    }
    Assert-True -Condition (@($forbidden).Count -eq 0) -Label 'P3 금지 에셋 없음'

    $start = Get-Content -LiteralPath (Join-Path $package 'start.cmd') -Raw
    Assert-True -Condition ($start -match 'where pwsh' -and $start -match 'ExecutionPolicy Bypass' -and $start -match 'S-1-16-12288') -Label 'P4 start.cmd 가드'

    $launch = Join-Path $package 'launch.js'
    & cscript.exe //E:JScript //B //NoLogo $launch --dry-run 2>&1 | Out-Null
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Label 'P4b launch.js JScript 파싱/드라이런'

    $zip = Join-Path $tmp 'DSH-Notify-Portable-test.zip'
    Assert-True -Condition (Test-Path -LiteralPath $zip) -Label 'P5 ZIP 생성'
    Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $tmp 'SHA256SUMS.txt') -Raw) -match '[0-9A-F]{64}') -Label 'P5b SHA256'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "portable-package: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
