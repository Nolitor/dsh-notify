<#
.SYNOPSIS    코어 팝업 모듈(ui\popup.ps1)이 요구 함수를 노출하는지 검증한다.
.DESCRIPTION 실제 창/소리는 스모크로 확인하고, 여기서는 STA에서 모듈을 로드해
             Show-NotifyPopup·Start-PopupSound·Stop-PopupSound 가 정의되는지만 본다.
.CONTRACT    ui\popup.ps1, core.ps1
.INPUTS      없음.
.OUTPUTS     PASS/FAIL 리포트.
.SIDE-EFFECTS 없음 (창을 띄우지 않는다).
.TESTS       docs\dsh-harness-notify-spec.md §4
.NOTES       Add-Type 은 STA 자식 프로세스에서 수행한다.
#>

#region INDEX
#   Assert-True  조건 비교
#   (main)       모듈 로드, 함수 존재, ding.wav 존재
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

$probe = @'
. "__ROOT__\ui\popup.ps1"
"Show-NotifyPopup=" + [bool](Get-Command Show-NotifyPopup -ErrorAction SilentlyContinue)
"Start-PopupSound=" + [bool](Get-Command Start-PopupSound -ErrorAction SilentlyContinue)
"Stop-PopupSound=" + [bool](Get-Command Stop-PopupSound -ErrorAction SilentlyContinue)
'@
$probe = $probe.Replace('__ROOT__', $repoRoot)
$path = Join-Path $env:TEMP ('dsh-popup-module-' + [guid]::NewGuid().ToString('N') + '.ps1')
Set-Content -LiteralPath $path -Value $probe -Encoding UTF8
$output = & pwsh -Sta -NoProfile -File $path 2>&1
Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
$text = ($output -join ' ')

Assert-True -Condition ($LASTEXITCODE -eq 0) -Label 'P1 모듈 로드'
Assert-True -Condition ($text -match 'Show-NotifyPopup=True') -Label 'P2 Show-NotifyPopup'
Assert-True -Condition ($text -match 'Start-PopupSound=True') -Label 'P3 Start-PopupSound'
Assert-True -Condition ($text -match 'Stop-PopupSound=True') -Label 'P4 Stop-PopupSound'
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $repoRoot 'notify\ding.wav')) -Label 'P5 ding.wav 존재'
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $repoRoot 'notify\play-wav.ps1')) -Label 'P6 play-wav.ps1 존재'
$pwBytes = [System.IO.File]::ReadAllBytes((Join-Path $repoRoot 'notify\play-wav.ps1'))
Assert-True -Condition ($pwBytes.Length -ge 3 -and $pwBytes[0] -eq 0xEF -and $pwBytes[1] -eq 0xBB -and $pwBytes[2] -eq 0xBF) -Label 'P7 play-wav BOM (5.1)'

Write-Host ''
Write-Host "popup-request: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
