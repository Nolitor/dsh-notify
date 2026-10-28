<#
.SYNOPSIS    트레이 자동 실행 토글의 Startup .lnk 생성/삭제를 검증한다.
.DESCRIPTION 임시 Startup 폴더를 사용해 Set-NotifyAutostart가 launch.js를 wscript.exe로
             실행하는 WindowStyle=7 바로가기를 만들고, 해제 시 삭제하는지 확인한다.
.CONTRACT    app\tray.ps1
.INPUTS      없음.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 통과.
.SIDE-EFFECTS 임시 .lnk 생성·삭제.
.TESTS       tests\run-all.ps1
.NOTES       실제 사용자 Startup 폴더는 건드리지 않는다.
#>

#region INDEX
#   Assert-True   조건 비교
#   (main)        A1 초기 꺼짐, A2 생성, A3 wscript/launch.js/WindowStyle, A4 해제
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'app\tray.ps1')

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-autostart-' + [guid]::NewGuid().ToString('N'))
$startup = Join-Path $tmp 'Startup'
New-Item -ItemType Directory -Path $startup -Force | Out-Null
$launch = Join-Path $repoRoot 'launch.js'
$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
$icon = Join-Path $repoRoot 'ui\icons\neutral-green.ico'
try {
    Assert-True -Condition (-not (Test-NotifyAutostart -StartupDir $startup)) -Label 'A1 초기 꺼짐'

    $created = Set-NotifyAutostart -Enabled $true -StartupDir $startup -AppRoot $repoRoot -StartCmd $launch -IconPath $icon
    Assert-True -Condition ($created -and (Test-NotifyAutostart -StartupDir $startup)) -Label 'A2 바로가기 생성'

    $lnk = Get-NotifyStartupShortcutPath -StartupDir $startup
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnk)
    Assert-True -Condition ($shortcut.TargetPath -eq $wscript) -Label 'A3 대상 wscript.exe (무음)'
    Assert-True -Condition ($shortcut.Arguments -like '*launch.js*') -Label 'A3b 인수 launch.js'
    Assert-True -Condition ($shortcut.WorkingDirectory -eq $repoRoot) -Label 'A3c WorkingDirectory'
    Assert-True -Condition ($shortcut.WindowStyle -eq 7) -Label 'A3d WindowStyle 7'
    Assert-True -Condition ($shortcut.IconLocation -like '*neutral-green.ico*') -Label 'A3e 중립 아이콘'

    [void](Set-NotifyAutostart -Enabled $false -StartupDir $startup)
    Assert-True -Condition (-not (Test-NotifyAutostart -StartupDir $startup)) -Label 'A4 해제'

    # 기본값도 start.cmd가 아니라 launch.js를 골라야 한다.
    [void](Set-NotifyAutostart -Enabled $true -StartupDir $startup -AppRoot $repoRoot -IconPath $icon)
    $defaultShortcut = $shell.CreateShortcut((Get-NotifyStartupShortcutPath -StartupDir $startup))
    Assert-True -Condition ($defaultShortcut.TargetPath -eq $wscript -and $defaultShortcut.Arguments -like '*launch.js*') -Label 'A5 기본 타깃 launch.js'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "autostart: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
