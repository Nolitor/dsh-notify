<#
.SYNOPSIS    반투명 인디케이터 카드와 상주 창(WPF)을 만든다.
.DESCRIPTION 카드는 중앙 정렬만 쓴다. 상단 제목(상태 색), 가운데 digital-7 타이머, 필요할 때 현지 시각.
             강조는 타이머 하나. 창은 테두리 없음·Topmost·작업표시줄 미표시·전체 드래그.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §3.1
.INPUTS      View(Get-IndicatorView 결과), X/Y
.OUTPUTS     WPF Border(카드) / Window
.SIDE-EFFECTS 창 생성 시 화면 표시는 호출측이 결정.
.TESTS       tests\indicator-render.ps1 (픽셀·중앙 정렬), tests\font.ps1 (폰트)
.NOTES       WPF 는 STA 필수. digital-7 은 ui\assets 에 임베드하고 file:// URI 로 로드한다.
#>

#region INDEX
#   Get-TimerFontFamily   저장된 BYO 폰트 또는 시스템 폰트
#   New-IndicatorText     공통 TextBlock (기본 가운데 정렬)
#   New-IndicatorCard     카드 비주얼 (210x92, 중앙 정렬, radius 10)
#   Update-IndicatorCard  타이머 텍스트만 갱신 (1초 tick, 카드 재생성 없이)
#   Update-NotifyTimerFont 현재 카드의 타이머 폰트를 즉시 교체
#   New-IndicatorWindow   상주 창 (Topmost·드래그·폰트 드롭)
#endregion

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

if (-not (Get-Command Import-NotifyFontFile -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'app\font-loader.ps1')
}

$script:IndicatorWidth = 210
$script:IndicatorHeight = 92
$script:CardBackground = '#121212'
$script:TitleColor = '#4D6BFE'
$script:TextColor = '#F5F5F5'
$script:MutedColor = '#A3A3A3'
$script:SecondsColor = '#2C2C2C'
$script:SecondsColor = '#3A3A3A'

if ($null -eq (Get-Variable -Name NotifyFontRoot -Scope Script -ErrorAction SilentlyContinue)) {
    $script:NotifyFontRoot = ''
}

function Get-TimerFontFamily {
    $fontRoot = $script:NotifyFontRoot
    if ([string]::IsNullOrWhiteSpace($fontRoot)) {
        $fontRoot = $script:NotifyFontRoot = Get-NotifyFontRoot -AppRoot (Split-Path -Parent $PSScriptRoot)
    }
    $font = Get-NotifyStartupFont -FontRoot $fontRoot
    return $font.FontFamily
}

$script:TimerFont = Get-TimerFontFamily

function New-IndicatorText {
    param(
        [string] $Text,
        [double] $Size,
        [string] $Color = $script:TextColor,
        [bool]   $Bold = $false,
        [object] $FontFamily = $null
    )

    $block = New-Object System.Windows.Controls.TextBlock
    $block.Text = $Text
    $block.FontSize = $Size
    $block.FontFamily = if ($null -ne $FontFamily) { $FontFamily }
                        else { New-Object System.Windows.Media.FontFamily('Segoe UI') }
    $block.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Color))
    $block.TextAlignment = [System.Windows.TextAlignment]::Center
    $block.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    if ($Bold) { $block.FontWeight = [System.Windows.FontWeights]::SemiBold }
    return $block
}

function New-IndicatorCard {
    param([object] $View)

    $alpha = [byte][Math]::Round(255 * [double]$View.Opacity)

    $card = New-Object System.Windows.Controls.Border
    $card.Width = $script:IndicatorWidth
    $card.Height = $script:IndicatorHeight
    $card.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $card.Background = New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.Color]::FromArgb($alpha, 18, 18, 18))

    $grid = New-Object System.Windows.Controls.Grid

    $title = New-IndicatorText -Text $View.Title -Size 10 -Color $script:TitleColor
    $title.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    $title.Margin = New-Object System.Windows.Thickness(0, 7, 0, 0)
    [void]$grid.Children.Add($title)

    $timerRow = New-Object System.Windows.Controls.StackPanel
    $timerRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $timerRow.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $timerRow.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $timerMain = New-IndicatorText -Text $View.TimerMain -Size 46 -Color $View.TimerColor -FontFamily $script:TimerFont
    $timerMain.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $timerDim = New-IndicatorText -Text $View.TimerDim -Size 46 -Color $script:SecondsColor -FontFamily $script:TimerFont
    $timerDim.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

    [void]$timerRow.Children.Add($timerMain)
    [void]$timerRow.Children.Add($timerDim)
    [void]$grid.Children.Add($timerRow)

    $local = $null
    if (-not [string]::IsNullOrWhiteSpace($View.LocalLine)) {
        $local = New-IndicatorText -Text $View.LocalLine -Size 9 -Color $script:MutedColor
        $local.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
        $local.Margin = New-Object System.Windows.Thickness(0, 0, 0, 5)
        [void]$grid.Children.Add($local)
    }

    $card.Child = $grid
    $card.Tag = [pscustomobject]@{
        Title     = $title
        TimerMain = $timerMain
        TimerDim  = $timerDim
        Local     = $local
    }
    return $card
}

function Update-IndicatorCard {
    param([object] $Card, [object] $View)

    if ($null -eq $Card -or $null -eq $Card.Tag) { return }
    $refs = $Card.Tag
    $refs.Title.Text = $View.Title
    $refs.TimerMain.Text = $View.TimerMain
    $refs.TimerDim.Text = $View.TimerDim
    if ($null -ne $refs.Local) { $refs.Local.Text = $View.LocalLine }
}

function Update-NotifyTimerFont {
    param([object] $Window)

    if ($null -eq $Window -or $null -eq $Window.Content) { return }
    $refs = $Window.Content.Tag
    if ($null -eq $refs) { return }
    $refs.TimerMain.FontFamily = $script:TimerFont
    $refs.TimerDim.FontFamily = $script:TimerFont
}

function Set-NotifyDropHighlight {
    param([object] $Window, [bool] $Active)

    if ($null -eq $Window -or $null -eq $Window.Content) { return }
    $card = $Window.Content
    if ($Active) {
        Write-FontDropLog 'highlight-on'
        $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString('#4ADE80'))
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
    }
    else {
        $card.ClearValue([System.Windows.Controls.Border]::BorderBrushProperty)
        $card.ClearValue([System.Windows.Controls.Border]::BorderThicknessProperty)
    }
}

function Reset-NotifyDropHighlightIfExpired {
    param([object] $Window)

    if ($null -eq $script:FontHighlightUntil) { return }
    if ((Get-Date) -lt $script:FontHighlightUntil) { return }
    try {
        if ($null -ne $script:FontFeedbackTimer) { $script:FontFeedbackTimer.Stop() }
        Set-NotifyDropHighlight -Window $Window -Active $false
        $script:FontHighlightUntil = $null
        Write-FontDropLog 'highlight-reset-by-tick'
    }
    catch {
        Write-FontDropLog ("highlight-reset error: {0}" -f $_.Exception.Message)
    }
}

function Write-FontDropLog {
    param([string] $Message)

    try {
        if (Get-Command Write-CoreLog -ErrorAction SilentlyContinue) {
            Write-CoreLog "font-drop: $Message"
            return
        }
    }
    catch { }
    try {
        $log = Join-Path (Split-Path -Parent $PSScriptRoot) 'cache\core.log'
        Add-Content -LiteralPath $log -Value ("{0} font-drop: {1}" -f (Get-Date).ToString('HH:mm:ss'), $Message) -ErrorAction SilentlyContinue
    }
    catch { }
}

function Enable-NotifyDropMessages {
    param([object] $Window)

    if (-not ('DshNotify.DropMessageFilter' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace DshNotify {
    public static class DropMessageFilter {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ChangeWindowMessageFilterEx(IntPtr hwnd, uint message, uint action, IntPtr changeFilterStruct);
        [DllImport("shell32.dll", SetLastError = true)]
        public static extern void DragAcceptFiles(IntPtr hwnd, bool accept);
    }
}
"@
    }

    try {
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
        $hwnd = $helper.Handle
        if ($hwnd -eq [IntPtr]::Zero) {
            Write-FontDropLog 'message-filter skipped: hwnd=0'
            return
        }
        [DshNotify.DropMessageFilter]::DragAcceptFiles($hwnd, $true)
        foreach ($message in @(0x0233, 0x004A, 0x0049)) {
            $ok = [DshNotify.DropMessageFilter]::ChangeWindowMessageFilterEx($hwnd, [uint32]$message, 1, [IntPtr]::Zero)
            Write-FontDropLog ("message-filter 0x{0:X4} allowed={1}" -f $message, $ok)
        }
    }
    catch {
        Write-FontDropLog ("message-filter error: {0}" -f $_.Exception.Message)
    }
}

function Get-NotifyDroppedFontFile {
    param([object] $Data)

    try {
        if (-not $Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { return $null }
        $files = @($Data.GetData([System.Windows.DataFormats]::FileDrop))
        return @($files | Where-Object { Test-NotifyFontFile -Path "$_" }) | Select-Object -First 1
    }
    catch {
        Write-FontDropLog ("data-read error: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Import-NotifyDroppedFont {
    param([object] $Window, [object] $Data)

    try {
        $fontFile = Get-NotifyDroppedFontFile -Data $Data
        if ($null -eq $fontFile) {
            $script:LastFontDropError = 'no valid .ttf/.otf in drop data'
            Write-FontDropLog 'rejected: no valid font file'
            return $false
        }
        if ([string]::IsNullOrWhiteSpace($script:NotifyFontRoot)) {
            $script:NotifyFontRoot = Get-NotifyFontRoot -AppRoot (Split-Path -Parent $PSScriptRoot)
        }
        $font = Import-NotifyFontFile -Path "$fontFile" -FontRoot $script:NotifyFontRoot
        $script:TimerFont = $font.FontFamily
        $script:LastFontDropError = ''
        Update-NotifyTimerFont -Window $Window
        Write-FontDropLog ("applied family={0} path={1}" -f $font.FamilyName, $font.Path)
        Set-NotifyDropHighlight -Window $Window -Active $true
        $script:FontHighlightUntil = (Get-Date).AddMilliseconds(1200)
        if ($null -ne $script:FontFeedbackTimer) {
            $script:FontFeedbackTimer.Stop()
            $script:FontFeedbackTimer.Start()
        }
        return $true
    }
    catch {
        $script:LastFontDropError = $_.Exception.Message
        Write-FontDropLog ("error: {0}" -f $_.Exception.Message)
        Set-NotifyDropHighlight -Window $Window -Active $false
        return $false
    }
}

function New-IndicatorWindow {
    param([object] $View, [double] $X = 40, [double] $Y = 40)

    $window = New-Object System.Windows.Window
    $window.WindowStyle = [System.Windows.WindowStyle]::None
    $window.AllowsTransparency = $true
    $window.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::Transparent)
    $window.Topmost = $true
    $window.ShowInTaskbar = $false
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $window.Width = $script:IndicatorWidth
    $window.Height = $script:IndicatorHeight
    $window.Left = $X
    $window.Top = $Y
    $window.ShowActivated = $false
    $window.AllowDrop = $true
    $window.Content = New-IndicatorCard -View $View
    $dropTarget = $window.Content
    $dropTarget.AllowDrop = $true

    $window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch { } }.GetNewClosure())

    $script:FontDragLogged = $false
    foreach ($target in @($window, $dropTarget)) {
        $target.AllowDrop = $true

        $target.Add_PreviewDragEnter({
            param($sender, $eventArgs)
            if (-not $script:FontDragLogged) {
                $script:FontDragLogged = $true
                Write-FontDropLog 'preview-drag-enter'
            }
            $fontFile = Get-NotifyDroppedFontFile -Data $eventArgs.Data
            if ($null -ne $fontFile) {
                $eventArgs.Effects = [System.Windows.DragDropEffects]::Copy
                Set-NotifyDropHighlight -Window $window -Active $true
            }
            else {
                $eventArgs.Effects = [System.Windows.DragDropEffects]::None
            }
            $eventArgs.Handled = $true
        }.GetNewClosure())

        $target.Add_PreviewDragOver({
            param($sender, $eventArgs)
            $fontFile = Get-NotifyDroppedFontFile -Data $eventArgs.Data
            if ($null -ne $fontFile) {
                $eventArgs.Effects = [System.Windows.DragDropEffects]::Copy
            }
            else {
                $eventArgs.Effects = [System.Windows.DragDropEffects]::None
            }
            $eventArgs.Handled = $true
        }.GetNewClosure())

        $target.Add_PreviewDragLeave({
            param($sender, $eventArgs)
            $script:FontDragLogged = $false
            Set-NotifyDropHighlight -Window $window -Active $false
            $eventArgs.Handled = $true
        }.GetNewClosure())

        $target.Add_PreviewDrop({
            param($sender, $eventArgs)
            $script:FontDragLogged = $false
            $script:LastFontDropError = 'preview-drop-entered'
            Write-FontDropLog 'preview-drop-entered'
            Set-NotifyDropHighlight -Window $window -Active $false
            [void](Import-NotifyDroppedFont -Window $window -Data $eventArgs.Data)
            $eventArgs.Handled = $true
        }.GetNewClosure())
    }

    $window.Add_SourceInitialized({
        Enable-NotifyDropMessages -Window $window
    }.GetNewClosure())

    $script:FontHighlightUntil = $null
    $script:IndicatorWindow = $window
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(1200)
    $script:FontFeedbackTimer = $timer
    $timer.Add_Tick({
        try {
            $timer.Stop()
            Set-NotifyDropHighlight -Window $window -Active $false
            $script:FontHighlightUntil = $null
            $card = $window.Content
            Write-FontDropLog ("highlight-reset brush={0} thick={1}" -f $card.BorderBrush, $card.BorderThickness)
        }
        catch {
            Write-FontDropLog ("highlight-reset error: {0}" -f $_.Exception.Message)
        }
    }.GetNewClosure())

    return $window
}
