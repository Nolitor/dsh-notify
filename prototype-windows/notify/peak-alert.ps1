<#
.SYNOPSIS    세션/하네스 시작 시 피크 구간이면 즉시 토스트로 경고한다.
.DESCRIPTION providers\deepseek-peak.ps1 의 Get-State 로 현재 구간을 판정하고,
             피크(alert)일 때만 윈도 토스트를 띄운다. 오프피크면 조용히 종료한다.
             -Force 로 오프피크에서도 표시할 수 있고, -DryRun 은 XML 만 출력한다.
.CONTRACT    providers\deepseek-peak.ps1 (Get-State), notify\toast.ps1 (New-ToastXml)
.INPUTS      Now, CacheDir, Config, -NoFetch, -Force, -DryRun
.OUTPUTS     표시 경로: 없음(종료코드 0). dry-run: ToastGeneric XML 또는 무출력.
.SIDE-EFFECTS 실제 호출 시 윈도 토스트 1회 (5.1 자식 프로세스 경유).
.TESTS       tests\peak-alert.ps1 A-D
.NOTES       정책: 기본은 피크에서만. 플러그인은 세션 시작(또는 턴 시작)에서 1회 호출한다.
#>

#region INDEX
#   Get-PeakAlertMessage 상태 → {Title, Body} 또는 $null (피크 아니면 침묵)
#   (main)               Get-State → 메시지 → dry-run XML / send-toast.ps1 호출
#endregion

param(
    [datetime]  $Now,
    [string]    $CacheDir,
    [hashtable] $Config,
    [switch]    $NoFetch,
    [switch]    $Force,
    [switch]    $DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'providers\deepseek-peak.ps1')
. (Join-Path $PSScriptRoot 'toast.ps1')

function Get-PeakAlertMessage {
    param([object] $State, [switch] $Force)

    if ($null -eq $State) { return $null }
    if (-not $Force -and $State.Severity -ne 'alert') { return $null }

    $title = switch ("$($State.Severity)") {
        'alert' { '지금 PEAK · 100%' }
        'warn'  { '주의 구간' }
        default { 'OFF-PEAK · 50%' }
    }

    return [pscustomobject]@{
        Title = $title
        Body  = "$($State.NotifyText) $($State.Detail)"
    }
}

if ([string]::IsNullOrWhiteSpace($CacheDir)) { $CacheDir = Join-Path $repoRoot 'cache' }
if ($null -eq $Config) { $Config = @{} }

$stateParams = @{ Config = $Config; CacheDir = $CacheDir; NoFetch = $NoFetch }
if ($PSBoundParameters.ContainsKey('Now')) { $stateParams['Now'] = $Now }
$state = Get-State @stateParams

$message = Get-PeakAlertMessage -State $state -Force:$Force
if ($null -eq $message) { exit 0 }

if ($DryRun) {
    Write-Output (New-ToastXml -Title $message.Title -Body $message.Body)
    exit 0
}

& pwsh -NoProfile -NoLogo -File (Join-Path $PSScriptRoot 'send-toast.ps1') -Title $message.Title -Body $message.Body
exit $LASTEXITCODE
