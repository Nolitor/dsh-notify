<#
.SYNOPSIS    윈도 토스트를 띄우는 단발성 CLI 진입점.
.DESCRIPTION PS7 에서 호출되면 Windows PowerShell 5.1 자식 프로세스로 자기 자신을 다시 실행해 표시한다.
             포트·웹서버·데몬 없이 한 번 뜨고 끝난다. -DryRun 이면 XML 만 출력한다.
.CONTRACT    notify\toast.ps1 — New-ToastXml, Send-WindowsToast
.INPUTS      Title, Body, AppId, -SendDirect(내부용), -DryRun
.OUTPUTS     표시 경로: 없음(종료코드 0). dry-run: ToastGeneric XML.
.SIDE-EFFECTS 실제 호출 시 윈도 알림 표시 (Focus Assist 에 따라 보이지 않을 수 있음).
.TESTS       tests\toast.ps1 T5-T6
.NOTES       DSH 플러그인이 이벤트에서 이 스크립트를 프로세스로 호출하는 것을 전제로 한다.
#>

#region INDEX
#   (main)  -DryRun → XML 출력 / PS7 → 5.1 재실행 / 5.1 → 표시
#endregion

param(
    [string] $Title = 'DSH Notify',
    [string] $Body = '',
    [string] $AppId = '',
    [switch] $SendDirect,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toast.ps1')

if ($DryRun) {
    Write-Output (New-ToastXml -Title $Title -Body $Body)
    exit 0
}

if (-not $SendDirect -and $PSVersionTable.PSVersion.Major -ge 7) {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $cliArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Title', $Title, '-Body', $Body, '-SendDirect')
    if (-not [string]::IsNullOrWhiteSpace($AppId)) { $cliArgs += @('-AppId', $AppId) }

    & $exe @cliArgs
    exit $LASTEXITCODE
}

$params = @{ Title = $Title; Body = $Body }
if (-not [string]::IsNullOrWhiteSpace($AppId)) { $params.AppId = $AppId }
Send-WindowsToast @params | Out-Null
exit 0
