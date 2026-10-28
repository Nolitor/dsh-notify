<#
.SYNOPSIS    상주 코어 프로세스에서 직접 띄우는 우하단 팝업 + 알림음.
.DESCRIPTION 브리지가 스폰한 자식 프로세스의 소리는 이 환경에서 잘렸다(사용자 실측).
             코어(DSH Notify)는 평소처럼 떠 있는 WPF 프로세스라 내부 테스트와 같은 경로로 소리가 난다.
             브리지는 cache\popup-request.json 만 남기고, 코어가 이 파일을 집어 팝업을 띄운다.
.CONTRACT    docs\dsh-harness-notify-spec.md §4
.INPUTS      Show-NotifyPopup: Title, Body, Seconds
.OUTPUTS     없음 (창 표시).
.SIDE-EFFECTS 화면 우하단 팝업, 알림음 재생.
.TESTS       tests\popup-request.ps1
.NOTES       창은 매번 새로 만들고 자동 닫힘. 소리는 SND_LOOP 로 3.6초 후 정지.
#>

#region INDEX
#   New-PopupWindow   다크 카드 창 생성 (자동 닫힘)
#   Start-PopupSound  ding.wav 재생 (SND_LOOP) / Stop-PopupSound
#   Show-NotifyPopup  창 표시 + 소리 + 정리 타이머
#endregion

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:PopupWidth = 340
$script:PopupHeight = 96
$script:PopupMargin = 24
$script:SoundEnabled = $true

if (-not ('Win32.PlayWowCore' -as [type])) {
    Add-Type -Namespace Win32 -Name PlayWowCore -MemberDefinition '[DllImport("winmm.dll", CharSet = CharSet.Unicode)] public static extern bool PlaySound(string s, IntPtr h, uint f);'
}

function New-PopupWindow {
    param([string] $Title, [string] $Body, [int] $Seconds)

    $work = [System.Windows.SystemParameters]::WorkArea
    $x = [Math]::Max($work.Left + $script:PopupMargin, $work.Right - $script:PopupWidth - $script:PopupMargin)
    $y = [Math]::Max($work.Top + $script:PopupMargin, $work.Bottom - $script:PopupHeight - $script:PopupMargin)

    $window = New-Object System.Windows.Window
    $window.WindowStyle = [System.Windows.WindowStyle]::None
    $window.AllowsTransparency = $true
    $window.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::Transparent)
    $window.Topmost = $true
    $window.ShowInTaskbar = $false
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $window.Width = $script:PopupWidth
    $window.Height = $script:PopupHeight
    $window.Left = $x
    $window.Top = $y
    $window.ShowActivated = $false

    $border = New-Object System.Windows.Controls.Border
    $border.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(236, 18, 18, 18))
    $border.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 42, 42, 42))
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    $border.CornerRadius = New-Object System.Windows.CornerRadius(12)
    $border.Padding = New-Object System.Windows.Thickness(16, 12, 16, 12)

    $stack = New-Object System.Windows.Controls.StackPanel

    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Semibold')
    $titleBlock.FontSize = 13
    $titleBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 245, 245, 245))
    [void]$stack.Children.Add($titleBlock)

    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $bodyBlock = New-Object System.Windows.Controls.TextBlock
        $bodyBlock.Text = $Body
        $bodyBlock.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
        $bodyBlock.FontSize = 11
        $bodyBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $bodyBlock.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
        $bodyBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 201, 201, 201))
        [void]$stack.Children.Add($bodyBlock)
    }

    $border.Child = $stack
    $window.Content = $border

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds([Math]::Max(1, $Seconds))
    $timer.Add_Tick({ $timer.Stop(); $window.Close() }.GetNewClosure())
    $timer.Start()

    return $window
}

$script:PopupSoundLog = Join-Path (Split-Path -Parent $PSScriptRoot) 'cache\popup-sound.log'
$script:SoundState = [pscustomobject]@{ Pids = @() }
$script:SoundProbeTimer = $null
$script:SoundCloseTimer = $null

function Write-PopupSoundLog {
    param([string] $Message)
    try { Add-Content -LiteralPath $script:PopupSoundLog -Value ("{0} {1}" -f (Get-Date).ToString('HH:mm:ss'), $Message) } catch { }
}

function Start-PopupSound {
    if (-not $script:SoundEnabled) { return }
    $wav = Join-Path (Split-Path -Parent $PSScriptRoot) 'notify\ding.wav'
    if (-not (Test-Path -LiteralPath $wav)) { return }

    Stop-PopupSound

    # 이 PC에서 WinMM/클라이언트 프로세스 경로는 소리가 앰프까지 도달하지 않는다(피크 0).
    # 사용자가 "들린다"고 확인한 유일한 경로: 기본 미디어 플레이어(Media Foundation)로 파일 열기.
    $before = @(Get-Process -Name 'Microsoft.Media.Player' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    Start-Process explorer.exe -ArgumentList "`"$wav`"" | Out-Null
    Write-PopupSoundLog "shell open player wav=$wav"

    $beforeIds = $before
    $state = [pscustomobject]@{ Pids = @() }
    $script:SoundState = $state

    $probe = New-Object System.Windows.Threading.DispatcherTimer
    $probe.Interval = [TimeSpan]::FromMilliseconds(1200)
    $script:SoundProbeTimer = $probe
    $probe.Add_Tick({
        $probe.Stop()
        $state.Pids = @(Get-Process -Name 'Microsoft.Media.Player' -ErrorAction SilentlyContinue |
            Where-Object { $beforeIds -notcontains $_.Id } | ForEach-Object { $_.Id })
        Write-PopupSoundLog "player pids=$($state.Pids -join ',')"
    }.GetNewClosure())
    $probe.Start()

    $close = New-Object System.Windows.Threading.DispatcherTimer
    $close.Interval = [TimeSpan]::FromSeconds(3.4)
    $script:SoundCloseTimer = $close
    $close.Add_Tick({
        $close.Stop()
        foreach ($pidValue in $state.Pids) {
            try { $p = Get-Process -Id $pidValue -ErrorAction SilentlyContinue; if ($p -and -not $p.HasExited) { $p.Kill(); Write-PopupSoundLog "player killed $pidValue" } } catch { }
        }
        $state.Pids = @()
    }.GetNewClosure())
    $close.Start()
}

function Stop-PopupSound {
    if ($null -ne $script:SoundProbeTimer) { $script:SoundProbeTimer.Stop(); $script:SoundProbeTimer = $null }
    if ($null -ne $script:SoundCloseTimer) { $script:SoundCloseTimer.Stop(); $script:SoundCloseTimer = $null }
    if ($null -ne $script:SoundState) {
        foreach ($pidValue in $script:SoundState.Pids) {
            try { $p = Get-Process -Id $pidValue -ErrorAction SilentlyContinue; if ($p -and -not $p.HasExited) { $p.Kill() } } catch { }
        }
        $script:SoundState.Pids = @()
    }
    try { [void][Win32.PlayWowCore]::PlaySound($null, [IntPtr]::Zero, 0) } catch { }
}

function Show-NotifyPopup {
    param([string] $Title = 'DSH 알림', [string] $Body = '', [int] $Seconds = 6)

    $window = New-PopupWindow -Title $Title -Body $Body -Seconds $Seconds
    $window.Add_MouseLeftButtonDown({ $window.Close() }.GetNewClosure())
    $window.Show()

    return $window
}
