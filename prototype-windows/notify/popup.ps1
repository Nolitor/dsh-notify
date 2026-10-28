<#
.SYNOPSIS    우하단 커스텀 팝업 (WPF) — DSH 이벤트 알림을 확실히 보이게 띄운다.
.DESCRIPTION 윈도 토스트는 OS 가 "전달됨"으로 기록해도 배너가 억제될 수 있다(집중 지원·전체화면 등).
             DSH Notify 는 자체 WPF 창으로 우하단에 6초 표시하고, 클릭하면 즉시 닫는다.
             포트·데몬 없이 `pwsh -Sta -File notify\popup.ps1` 로 한 번 뜨고 스스로 종료한다.
.CONTRACT    docs\dsh-harness-notify-spec.md §4 (표시 계층)
.INPUTS      Title, Body, Seconds, DryRun
.OUTPUTS     DryRun 이면 기하/문구 한 줄. 아니면 창을 띄우고 종료.
.SIDE-EFFECTS 실제 호출 시 화면 우하단 팝업 표시.
.TESTS       tests\popup.ps1
.NOTES       카드(ui\indicator.ps1)와 같은 다크 톤. 카드 위치와 겹치지 않게 화면 우하단 고정.
#>

#region INDEX
#   New-PopupWindow   다크 카드 창 생성 (제목·본문·자동 닫힘·클릭 닫힘)
#   Start-NotifySound 윈도 알림 WAV 재생 (실패 시 Asterisk, -Silent 면 생략)
#   (main)            -DryRun 이면 기하만 출력, 아니면 STA 디스패처로 표시
#endregion

param(
    [string] $Title = 'DSH 알림',
    [string] $Body = '',
    [int] $Seconds = 6,
    [switch] $Silent,
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$width = 340
$height = 96
$margin = 24

$work = [System.Windows.SystemParameters]::WorkArea
$x = [Math]::Max($work.Left + $margin, $work.Right - $width - $margin)
$y = [Math]::Max($work.Top + $margin, $work.Bottom - $height - $margin)

if ($DryRun) {
    "popup: title='$Title' body='$Body' x=$x y=$y w=$width h=$height seconds=$Seconds sound=$(-not $Silent)"
    exit 0
}

function Start-NotifySound {
    if ($Silent) { return }

    $custom = Join-Path $PSScriptRoot 'ding.wav'
    $fallback = Join-Path $env:WINDIR 'Media\Windows Notify System Generic.wav'
    $wav = if (Test-Path -LiteralPath $custom) { $custom } else { $fallback }
    $log = Join-Path (Split-Path -Parent $PSScriptRoot) 'cache\popup-sound.log'
    $write = {
        param([string] $Message)
        try { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date).ToString('HH:mm:ss'), $Message) } catch { }
    }

    & $write "attempt wav=$wav exists=$(Test-Path -LiteralPath $wav)"

    try {
        if (-not ('Win32.PlayWow' -as [type])) {
            Add-Type -Namespace Win32 -Name PlayWow -MemberDefinition '[DllImport("winmm.dll", CharSet = CharSet.Unicode)] public static extern bool PlaySound(string s, IntPtr h, uint f);'
        }
        $ok = [Win32.PlayWow]::PlaySound($wav, [IntPtr]::Zero, 0x20009)
        & $write "PlaySound(loop)=$ok"
        if ($ok) { return }
    }
    catch { & $write "PlaySound ERR: $($_.Exception.Message)" }

    try {
        $player = New-Object System.Media.SoundPlayer $wav
        $player.Play()
        & $write 'SoundPlayer played'
        return $player
    }
    catch { & $write "SoundPlayer ERR: $($_.Exception.Message)" }

    try { [System.Media.SystemSounds]::Asterisk.Play(); & $write 'Asterisk played' } catch { & $write "Asterisk ERR: $($_.Exception.Message)" }
}

function Stop-NotifySound {
    try {
        if ('Win32.PlayWow' -as [type]) { [Win32.PlayWow]::PlaySound($null, [IntPtr]::Zero, 0) }
    }
    catch { }
}

function New-PopupWindow {
    param([string] $Title, [string] $Body, [int] $Seconds, [double] $X, [double] $Y, [double] $Width, [double] $Height)

    $window = New-Object System.Windows.Window
    $window.WindowStyle = [System.Windows.WindowStyle]::None
    $window.AllowsTransparency = $true
    $window.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::Transparent)
    $window.Topmost = $true
    $window.ShowInTaskbar = $false
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $window.Width = $Width
    $window.Height = $Height
    $window.Left = $X
    $window.Top = $Y
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

    $window.Add_MouseLeftButtonDown({ $window.Close() }.GetNewClosure())
    $window.Add_Closed({ $window.Dispatcher.InvokeShutdown() }.GetNewClosure())

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds([Math]::Max(1, $Seconds))
    $timer.Add_Tick({ $timer.Stop(); $window.Close() }.GetNewClosure())
    $timer.Start()

    return $window
}

$popup = New-PopupWindow -Title $Title -Body $Body -Seconds $Seconds -X $x -Y $y -Width $width -Height $height
$popup.Add_Closed({ Stop-NotifySound })
$popup.Show()
$null = Start-NotifySound

$soundStop = New-Object System.Windows.Threading.DispatcherTimer
$soundStop.Interval = [TimeSpan]::FromSeconds(3.6)
$soundStop.Add_Tick({ $soundStop.Stop(); Stop-NotifySound })
$soundStop.Start()

[System.Windows.Threading.Dispatcher]::Run()
