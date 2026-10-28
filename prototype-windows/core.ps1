<#
.SYNOPSIS    DSH Notify 상주 프로세스 — 반투명 카드 + 트레이.
.DESCRIPTION 단일 인스턴스로 실행되어 60초마다 provider 를 폴링하고, 1초마다 카운트다운을 갱신한다.
             severity 가 바뀔 때만 윈도 토스트를 1회 띄우고, 위치/표시 모드를 config.json 에 저장한다.
             displayMode=peakOnly 이면 오프피크에 카드를 숨긴다(트레이는 유지).
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §2.4 (갱신 주기), §3 (UI), §4 (설정), §5 (오류)
.INPUTS      config.json, providers\deepseek-peak.ps1, ui\*.ps1
.OUTPUTS     화면 카드 + 트레이 아이콘. 콘솔 출력 없음.
.SIDE-EFFECTS config.json/캐시 쓰기, 토스트 프로세스 호출, 트레이 상주.
.TESTS       tests\core-config.ps1 (설정), tests\presenter.ps1 (표시), 수동 스모크
.NOTES       pwsh -Sta 필수. start.vbs 가 이 조건으로 띄운다.
#>

param([int] $RunSeconds = 0)

#region INDEX
#   Read-NotifyState   마지막 severity 읽기
#   Save-NotifyState   마지막 severity 저장 (원자적)
#   Get-View           캐시된 상태 + 현지 줄 → 표시 모델
#   Update-Ui          변경 시에만 창 내용/가시성/트레이 갱신
#   Invoke-Poll        provider 호출 → 알림 판정 → 저장 → UI
#   Save-Position      현재 창 위치를 설정에 저장
#   Exit-App           저장·정리 후 종료
#   (main)             STA 확인 → 단일 인스턴스 → 창·트레이 → 타이머 → Dispatcher
#endregion

$ErrorActionPreference = 'Stop'

# Zero-flicker: detach the process from any inherited console before WPF starts.
# This protects launches from cmd.exe, shortcuts, and debuggers that still hand us a console.
try {
    if (-not ('DshNotify.ConsoleNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace DshNotify {
    public static class ConsoleNative {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool FreeConsole();
    }
}
'@ -ErrorAction Stop
    }
    [void][DshNotify.ConsoleNative]::FreeConsole()
}
catch { }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = $PSScriptRoot
. (Join-Path $root 'config.ps1')
$script:dataRoot = Get-NotifyDataRoot -AppRoot $root
$script:NotifyFontRoot = Get-NotifyFontRoot -AppRoot $root -DataRoot $script:dataRoot
. (Join-Path $root 'app\font-loader.ps1')
. (Join-Path $root 'providers\deepseek-peak.ps1')
. (Join-Path $root 'ui\presenter.ps1')
. (Join-Path $root 'ui\indicator.ps1')
. (Join-Path $root 'app\tray.ps1')
. (Join-Path $root 'ui\popup.ps1')

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    Write-Error 'WPF 는 STA 가 필요합니다. pwsh -Sta -File core.ps1 로 실행하세요.'
    exit 2
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\DSHNotify')
if (-not $mutex.WaitOne(0)) {
    Write-Host 'DSH Notify 가 이미 실행 중입니다.'
    exit 0
}

$script:root = $root
$script:configPath = Join-Path $script:dataRoot 'config.json'
$script:cacheDir = Join-Path $script:dataRoot 'cache'
$script:notifyStatePath = Join-Path $script:cacheDir 'notify-state.json'
$script:logPath = Join-Path $script:cacheDir 'core.log'
$script:popupRequestPath = Join-Path $script:cacheDir 'popup-request.json'
$script:toastPath = Join-Path $root 'notify\send-toast.ps1'

function Write-CoreLog {
    param([string] $Message)
    try { Add-Content -LiteralPath $script:logPath -Value ("{0} {1}" -f (Get-Date).ToString('HH:mm:ss'), $Message) } catch { }
}

if (-not (Test-Path -LiteralPath $script:cacheDir)) {
    New-Item -ItemType Directory -Path $script:cacheDir -Force | Out-Null
}

function Read-NotifyState {
    if (-not (Test-Path -LiteralPath $script:notifyStatePath)) { return '' }
    try {
        $raw = Get-Content -LiteralPath $script:notifyStatePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $property = $raw.PSObject.Properties['severity']
        if ($null -ne $property) { return "$($property.Value)" }
    }
    catch { }
    return ''
}

function Save-NotifyState {
    $payload = @{ severity = $script:severitySeen; at = (Get-Date).ToString('o') } | ConvertTo-Json
    $temp = "$script:notifyStatePath.tmp"
    Set-Content -LiteralPath $temp -Value $payload -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $script:notifyStatePath -Force
}

function Get-View {
    param([object] $State)

    $localLine = ''
    if ($null -ne $script:region -and $script:region.Mismatch -and $null -ne $State.NextChangeAt) {
        $localLine = Format-RegionWindow -UtcNow ([datetime]::UtcNow) -NextChangeAt ([datetime]$State.NextChangeAt) -TimeZone $script:region.Region
    }

    $view = Get-IndicatorView -State $State -Config @{
        displayMode = $script:config.DisplayMode
        opacity     = $script:config.Opacity
    } -Now (Get-Date) -LocalLine $localLine
    return $view
}

function Update-Ui {
    $view = Get-View -State $script:state
    $key = "$($view.Title)|$($view.LocalLine)|$($view.Visible)"
    if ($key -eq $script:lastKey) {
        Update-IndicatorCard -Card $script:window.Content -View $view
        return
    }
    $script:lastKey = $key

    $script:window.Content = New-IndicatorCard -View $view
    Write-CoreLog "ui: next=$($script:state.NextChangeAt) $($view.Title) $($view.TimerMain)$($view.TimerDim)"
    $show = $view.Visible -and -not $script:cardHidden
    if ($show) {
        if (-not $script:window.IsVisible) { $script:window.Show() }
    }
    else {
        $script:window.Hide()
    }
    Sync-TrayChecks

    $tooltip = "$($view.Title)  $($view.TimerMain)"
    if (-not [string]::IsNullOrWhiteSpace($script:config.Warning)) { $tooltip = "$tooltip — $($script:config.Warning)" }
    Set-TrayState -Tray $script:tray -View $view -Tooltip $tooltip
}

function Invoke-Poll {
    if ($null -ne $script:syncJob) { return }
    try {
        $newState = Get-State -Now (Get-Date) -Config $script:config.ProviderConfig -CacheDir $script:cacheDir
        if ($null -eq $newState) { return }

        $script:state = $newState

        if (((Get-Date) - $script:lastRegionCheck).TotalHours -ge 24) {
            try { $script:region = Get-PeakReferenceTimeZones -CacheDir $script:cacheDir } catch { }
            $script:lastRegionCheck = Get-Date
        }

        $view = Get-View -State $script:state
        if ($script:config.Notifications -and (Test-NotifyTransition -PreviousSeverity $script:severitySeen -CurrentSeverity $script:state.Severity -NotifyOnChange $script:config.NotifyOnChange)) {
            $body = "$($script:state.NotifyText) $($script:state.Detail)"
            Start-Process -FilePath 'pwsh' -WindowStyle Hidden -ArgumentList @(
                '-NoProfile', '-NoLogo', '-File', $script:toastPath, '-Title', $view.Title, '-Body', $body
            ) | Out-Null
        }

        $script:severitySeen = $script:state.Severity
        Save-NotifyState
        Update-Ui
    }
    catch {
        Write-CoreLog "poll failed — $($_.Exception.Message)"
    }
}

function Save-Position {
    if ($null -eq $script:window) { return }
    try {
        $script:config.PositionX = [int]$script:window.Left - $script:oledOffsetX
        $script:config.PositionY = [int]$script:window.Top - $script:oledOffsetY
        $script:oledBaseX = $script:config.PositionX
        $script:oledBaseY = $script:config.PositionY
        Save-NotifyConfig -Path $script:configPath -Config $script:config
    }
    catch { }
}

function Apply-OledStep {
    $offsets = @(@(0, 0), @(5, 0), @(5, 5), @(0, 5))
    $script:oledStep = ($script:oledStep + 1) % $offsets.Count
    $dx = $offsets[$script:oledStep][0]
    $dy = $offsets[$script:oledStep][1]

    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $x = [int][Math]::Min($script:oledBaseX + $dx, $bounds.Right - 80)
    $y = [int][Math]::Min($script:oledBaseY + $dy, $bounds.Bottom - 40)

    $script:oledOffsetX = $dx
    $script:oledOffsetY = $dy
    $script:window.Left = $x
    $script:window.Top = $y
}

function Start-OledTimer {
    if ($null -eq $script:oledTimer) {
        $script:oledTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:oledTimer.Add_Tick({ if ($script:config.OledProtection) { Apply-OledStep } })
    }
    $script:oledTimer.Interval = [TimeSpan]::FromSeconds([Math]::Max(5, $script:config.OledIntervalSeconds))
    $script:oledTimer.Start()
}

function Stop-OledTimer {
    if ($null -ne $script:oledTimer) { $script:oledTimer.Stop() }
    $script:oledOffsetX = 0
    $script:oledOffsetY = 0
    $script:oledStep = 0
    if ($null -ne $script:window) {
        $script:window.Left = $script:oledBaseX
        $script:window.Top = $script:oledBaseY
    }
}

function Sync-TrayChecks {
    $visible = $false
    if ($null -ne $script:window) { $visible = [bool]$script:window.IsVisible }
    Set-TrayChecks -Tray $script:tray -NotifyEnabled $script:config.Notifications -DisplayMode $script:config.DisplayMode -OledEnabled $script:config.OledProtection -AutostartEnabled (Test-NotifyAutostart) -CardVisible $visible
}

function Invoke-PopupRequests {
    if (-not (Test-Path -LiteralPath $script:popupRequestPath)) { return }
    try {
        $raw = Get-Content -LiteralPath $script:popupRequestPath -Raw -Encoding UTF8
        Remove-Item -LiteralPath $script:popupRequestPath -Force -ErrorAction SilentlyContinue
        $data = $raw | ConvertFrom-Json
        if ($null -eq $data) { return }
        if (-not $script:config.Notifications) { return }
        Show-NotifyPopup -Title "$($data.title)" -Body "$($data.body)" | Out-Null
        Write-CoreLog "popup request consumed: $($data.title)"
    }
    catch {
        Write-CoreLog "popup request failed — $($_.Exception.Message)"
    }
}

function Start-InitialSync {
    if ($null -ne $script:syncJob) { return }
    Write-CoreLog 'initial sync: start'

    $configJson = $script:config.ProviderConfig | ConvertTo-Json -Compress
    $script:syncJob = Start-ThreadJob -ScriptBlock {
        param($Root, $ConfigJson, $CacheDir)

        . (Join-Path $Root 'providers\deepseek-peak.ps1')
        $providerConfig = $ConfigJson | ConvertFrom-Json -AsHashtable
        $state = Get-State -Now (Get-Date) -Config $providerConfig -CacheDir $CacheDir

        $region = $null
        try {
            $reference = Get-PeakReferenceTimeZones -CacheDir $CacheDir
            $region = [pscustomobject]@{ Id = $reference.RegionId; Mismatch = $reference.Mismatch; Label = $reference.Label }
        }
        catch { }

        $next = ''
        if ($null -ne $state.NextChangeAt) { $next = ([datetime]$state.NextChangeAt).ToString('o') }

        [pscustomobject]@{
            State  = [pscustomobject]@{
                Id = $state.Id; Label = $state.Label; Severity = $state.Severity
                Headline = $state.Headline; Detail = $state.Detail
                NextChangeAt = $next; NotifyText = $state.NotifyText
            }
            Region = $region
        } | ConvertTo-Json -Depth 5 -Compress
    } -ArgumentList $script:root, $configJson, $script:cacheDir
    Write-CoreLog "initial sync: job=$($script:syncJob.State)"
}

function Complete-InitialSync {
    if ($null -eq $script:syncJob) { return }
    if ($script:syncJob.State -eq 'Running' -or $script:syncJob.State -eq 'NotStarted') { return }

    if ($script:syncJob.State -eq 'Completed') {
        try {
            $json = $script:syncJob | Receive-Job
            $data = $json | ConvertFrom-Json

            $next = $null
            if (-not [string]::IsNullOrWhiteSpace($data.State.NextChangeAt)) {
                $next = [datetime]::Parse(
                    $data.State.NextChangeAt,
                    [cultureinfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind)
                if ($next.Kind -eq [System.DateTimeKind]::Unspecified) {
                    $next = [datetime]::SpecifyKind($next, [System.DateTimeKind]::Utc)
                }
            }

            $script:state = [pscustomobject]@{
                Id           = $data.State.Id
                Label        = $data.State.Label
                Severity     = $data.State.Severity
                Headline     = $data.State.Headline
                Detail       = $data.State.Detail
                NextChangeAt = $next
                NotifyText   = $data.State.NotifyText
            }

            if ($null -ne $data.Region) {
                try {
                    $timeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($data.Region.Id)
                    $script:region = [pscustomobject]@{
                        Region   = $timeZone
                        Mismatch = [bool]$data.Region.Mismatch
                        Label    = $data.Region.Label
                    }
                    $script:lastRegionCheck = Get-Date
                }
                catch { }
            }

            $script:severitySeen = $script:state.Severity
            Save-NotifyState
            $script:lastKey = ''
            Update-Ui
            Write-CoreLog "initial sync: applied $($script:state.Severity) $($script:state.NextChangeAt)"
        }
        catch {
            Write-CoreLog "initial sync: apply failed — $($_.Exception.Message)"
        }
    }
    else {
        Write-CoreLog "initial sync: job $($script:syncJob.State)"
    }

    $script:syncJob | Remove-Job -Force -ErrorAction SilentlyContinue
    $script:syncJob = $null
    $script:oledOffsetX = 0
    $script:oledOffsetY = 0
    $script:oledStep = 0
    $script:oledTimer = $null
}

function Exit-App {
    $script:pollTimer.Stop()
    $script:tickTimer.Stop()
    if ($null -ne $script:oledTimer) { $script:oledTimer.Stop() }
    if ($null -ne $script:syncTimer) { $script:syncTimer.Stop() }
    if ($null -ne $script:initialSyncTimer) { $script:initialSyncTimer.Stop() }
    if ($null -ne $script:syncJob) {
        $script:syncJob | Remove-Job -Force -ErrorAction SilentlyContinue
        $script:syncJob = $null
    }
    Save-Position
    try { Save-NotifyConfig -Path $script:configPath -Config $script:config } catch { }
    if ($null -ne $script:tray) {
        $script:tray.Icon.Visible = $false
        $script:tray.Icon.Dispose()
    }
    if ($null -ne $script:window) { $script:window.Close() }
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}

try {
    $script:config = Get-NotifyConfig -Path $script:configPath
    $script:severitySeen = Read-NotifyState
    $script:region = $null
    $script:lastRegionCheck = [datetime]::MinValue
    $script:cardHidden = $false
    $script:lastKey = ''
    Write-CoreLog "start (mode=$($script:config.DisplayMode), opacity=$($script:config.Opacity))"

    $script:syncJob = $null
    $script:oledOffsetX = 0
    $script:oledOffsetY = 0
    $script:oledStep = 0
    $script:oledTimer = $null

    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $position = Get-ClampedPosition -X $script:config.PositionX -Y $script:config.PositionY -Bounds $bounds
    $script:config.PositionX = $position.X
    $script:config.PositionY = $position.Y

    # 즉시 표시용 자리 상태 — 동기화(공휴일/지역)는 5초 뒤 백그라운드에서 시작한다.
    $script:state = [pscustomobject]@{
        Id           = 'deepseek-peak'
        Label        = 'DeepSeek'
        Severity     = 'ok'
        Headline     = 'OFF-PEAK · 50%'
        Detail       = ''
        NextChangeAt = (Get-Date)
        NotifyText   = ''
    }
    $initialView = Get-View -State $script:state

    $script:window = New-IndicatorWindow -View $initialView -X $script:config.PositionX -Y $script:config.PositionY
    $script:oledBaseX = $script:config.PositionX
    $script:oledBaseY = $script:config.PositionY
    $script:window.Add_MouseLeftButtonUp({ Save-Position })
    $script:window.Add_Closing({ Save-Position })

    $iconPaths = @{
        green = Join-Path $root 'ui\icons\neutral-green.ico'
        red   = Join-Path $root 'ui\icons\neutral-red.ico'
    }
    if (-not (Test-Path -LiteralPath $iconPaths.green)) { $iconPaths.green = Join-Path $root 'ui\icons\deepseek-green.ico' }
    if (-not (Test-Path -LiteralPath $iconPaths.red)) { $iconPaths.red = Join-Path $root 'ui\icons\deepseek-red.ico' }

    $onRefresh = { Invoke-Poll }
    $onAlways = {
        $script:config.DisplayMode = 'always'
        Save-NotifyConfig -Path $script:configPath -Config $script:config
        $script:lastKey = ''
        Update-Ui
    }
    $onPeakOnly = {
        $script:config.DisplayMode = 'peakOnly'
        Save-NotifyConfig -Path $script:configPath -Config $script:config
        $script:lastKey = ''
        Update-Ui
    }
    $onReset = {
        $script:config.PositionX = 40
        $script:config.PositionY = 40
        $script:oledBaseX = 40
        $script:oledBaseY = 40
        $script:oledOffsetX = 0
        $script:oledOffsetY = 0
        $script:oledStep = 0
        $script:window.Left = 40
        $script:window.Top = 40
        Save-NotifyConfig -Path $script:configPath -Config $script:config
    }
    $onToggle = {
        $script:cardHidden = -not $script:cardHidden
        $script:lastKey = ''
        Update-Ui
    }
    $onToggleNotifications = {
        $script:config.Notifications = -not $script:config.Notifications
        Save-NotifyConfig -Path $script:configPath -Config $script:config
        Sync-TrayChecks
    }
    $onToggleOled = {
        $script:config.OledProtection = -not $script:config.OledProtection
        Save-NotifyConfig -Path $script:configPath -Config $script:config
        Sync-TrayChecks
        if ($script:config.OledProtection) { Start-OledTimer }
        else { Stop-OledTimer }
    }
    $onToggleAutostart = {
        try {
            $enable = -not (Test-NotifyAutostart)
            [void](Set-NotifyAutostart -Enabled $enable -AppRoot $root -StartCmd (Join-Path $root 'launch.js') -IconPath $iconPaths['green'])
            Write-CoreLog "autostart=$enable"
        }
        catch {
            Write-CoreLog "autostart failed — $($_.Exception.Message)"
        }
        Sync-TrayChecks
    }
    $onExit = { Exit-App }

    $script:tray = New-NotifyTray -Icons $iconPaths -OnRefresh $onRefresh -OnAlways $onAlways `
        -OnPeakOnly $onPeakOnly -OnReset $onReset -OnToggle $onToggle -OnExit $onExit `
        -OnToggleNotifications $onToggleNotifications -NotifyEnabled $script:config.Notifications -DisplayMode $script:config.DisplayMode `
        -OnToggleOled $onToggleOled -OledEnabled $script:config.OledProtection -CardVisible $true `
        -OnToggleAutostart $onToggleAutostart -AutostartEnabled (Test-NotifyAutostart)

    if ($initialView.Visible -and -not $script:cardHidden) { $script:window.Show() }
    else { $script:window.Hide() }

    # Migrate an existing Startup shortcut from the old start.cmd target to the silent launcher.
    if (Test-NotifyAutostart) {
        try {
            [void](Set-NotifyAutostart -Enabled $true -AppRoot $root -StartCmd (Join-Path $root 'launch.js') -IconPath $iconPaths['green'])
        }
        catch {
            Write-CoreLog "autostart migration failed — $($_.Exception.Message)"
        }
    }
    Sync-TrayChecks

    Set-TrayState -Tray $script:tray -View $initialView -Tooltip "$($initialView.Title)  $($initialView.TimerText)"
    $script:lastKey = "$($initialView.Title)|$($initialView.LocalLine)|$($initialView.Visible)"

    $script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:pollTimer.Interval = [TimeSpan]::FromSeconds([Math]::Max(10, $script:config.PollSeconds))
    $script:pollTimer.Add_Tick({ Invoke-Poll })
    $script:pollTimer.Start()

    $script:tickTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:tickTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:tickTimer.Add_Tick({ Update-Ui; Invoke-PopupRequests; Reset-NotifyDropHighlightIfExpired -Window $script:window })
    $script:tickTimer.Start()

    # 디스패처 예외로 상주 앱이 죽지 않게 한다(팝업 타이머 등).
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.add_UnhandledException({
        param($sender, $eventArgs)
        $eventArgs.Handled = $true
        try { Write-CoreLog "dispatcher error: $($eventArgs.Exception.Message)" } catch { }
    })

    if ($script:config.OledProtection) { Start-OledTimer }

    # 5초 뒤 백그라운드 동기화 시작 → 300ms 간격으로 완료 확인
    $script:syncTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:syncTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:syncTimer.Add_Tick({
        Complete-InitialSync
        if ($null -eq $script:syncJob) { $script:syncTimer.Stop() }
    })

    $script:initialSyncTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:initialSyncTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:initialSyncTimer.Add_Tick({
        $script:initialSyncTimer.Stop()
        Start-InitialSync
        $script:syncTimer.Start()
    })
    $script:initialSyncTimer.Start()

    if ($RunSeconds -gt 0) {
        $stopTimer = New-Object System.Windows.Threading.DispatcherTimer
        $stopTimer.Interval = [TimeSpan]::FromSeconds($RunSeconds)
        $stopTimer.Add_Tick({ $stopTimer.Stop(); Exit-App })
        $stopTimer.Start()
    }

    [System.Windows.Threading.Dispatcher]::Run()
}
finally {
    if ($null -ne $script:tray) {
        try { $script:tray.Icon.Visible = $false; $script:tray.Icon.Dispose() } catch { }
    }
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
