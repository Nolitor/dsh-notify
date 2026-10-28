<#
.SYNOPSIS    7세그먼트 숫자를 WPF 도형으로 그린다 (폰트 의존 없음).
.DESCRIPTION 각 세그먼트를 둥근 끝 선으로 그려 LED 시계 느낌을 낸다. 숫자 0-9 와 콜론만 지원한다.
             크기를 키워도 선 굵기가 비례해 선명하다.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §3.1 (타이머)
.INPUTS      Char 또는 Text, Height, Color, GhostColor(선택)
.OUTPUTS     Canvas(문자 1개) / StackPanel(문자열)
.SIDE-EFFECTS 없음 (WPF 객체 생성).
.TESTS       tests\segments.ps1 S1-S6, tests\indicator-render.ps1 (픽셀)
.NOTES       단위 박스 10x18, 선 굵기 1.9. 콜론은 점 2개.
#>

#region INDEX
#   Get-SevenSegmentMap   문자 → 켜진 세그먼트 목록
#   New-SevenSegmentChar  문자 1개 → Canvas
#   New-SevenSegmentTimer 문자열 → StackPanel (콜론 폭 좁음)
#endregion

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:SegmentMap = @{
    '0' = @('a', 'b', 'c', 'd', 'e', 'f')
    '1' = @('b', 'c')
    '2' = @('a', 'b', 'g', 'e', 'd')
    '3' = @('a', 'b', 'g', 'c', 'd')
    '4' = @('f', 'g', 'b', 'c')
    '5' = @('a', 'f', 'g', 'c', 'd')
    '6' = @('a', 'f', 'g', 'e', 'c', 'd')
    '7' = @('a', 'b', 'c')
    '8' = @('a', 'b', 'c', 'd', 'e', 'f', 'g')
    '9' = @('a', 'b', 'c', 'd', 'f', 'g')
}

function Get-SevenSegmentMap {
    param([char] $Char)

    $key = [string]$Char
    if ($key -eq ':') { return @() }
    if (-not $script:SegmentMap.ContainsKey($key)) { throw "지원하지 않는 문자: $Char" }
    return $script:SegmentMap[$key]
}

function New-SevenSegmentChar {
    param(
        [char]   $Char,
        [double] $Height = 32,
        [string] $Color = '#FF9F1C',
        [string] $GhostColor = ''
    )

    $unit = $Height / 18.0
    $thickness = 1.9 * $unit
    $pad = $thickness / 2
    $width = (10 * $unit) + $thickness

    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Height = (18 * $unit) + $thickness

    if ($Char -eq ':') {
        $canvas.Width = (3 * $unit) + $thickness
        $dotBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Color))
        foreach ($cy in @(0.38, 0.68)) {
            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 2.2 * $unit
            $dot.Height = 2.2 * $unit
            $dot.Fill = $dotBrush
            [System.Windows.Controls.Canvas]::SetLeft($dot, $pad)
            [System.Windows.Controls.Canvas]::SetTop($dot, ((18 * $unit * $cy) - (1.1 * $unit) + $pad))
            [void]$canvas.Children.Add($dot)
        }
        return $canvas
    }

    $canvas.Width = $width

    $points = @{
        'a' = @((((1.4) * $unit) + $pad), (((0.9) * $unit) + $pad), (((8.6) * $unit) + $pad), (((0.9) * $unit) + $pad))
        'b' = @((((9.1) * $unit) + $pad), (((1.6) * $unit) + $pad), (((9.1) * $unit) + $pad), (((8.4) * $unit) + $pad))
        'c' = @((((9.1) * $unit) + $pad), (((9.6) * $unit) + $pad), (((9.1) * $unit) + $pad), (((16.4) * $unit) + $pad))
        'd' = @((((1.4) * $unit) + $pad), (((17.1) * $unit) + $pad), (((8.6) * $unit) + $pad), (((17.1) * $unit) + $pad))
        'e' = @((((0.9) * $unit) + $pad), (((9.6) * $unit) + $pad), (((0.9) * $unit) + $pad), (((16.4) * $unit) + $pad))
        'f' = @((((0.9) * $unit) + $pad), (((1.6) * $unit) + $pad), (((0.9) * $unit) + $pad), (((8.4) * $unit) + $pad))
        'g' = @((((1.4) * $unit) + $pad), (((9.0) * $unit) + $pad), (((8.6) * $unit) + $pad), (((9.0) * $unit) + $pad))
    }

    if (-not [string]::IsNullOrWhiteSpace($GhostColor)) {
        $ghostBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($GhostColor))
        foreach ($key in $points.Keys) {
            $p = $points[$key]
            $line = New-Object System.Windows.Shapes.Line
            $line.X1 = $p[0]; $line.Y1 = $p[1]; $line.X2 = $p[2]; $line.Y2 = $p[3]
            $line.Stroke = $ghostBrush
            $line.StrokeThickness = $thickness
            $line.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
            $line.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
            [void]$canvas.Children.Add($line)
        }
    }

    $brush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Color))
    foreach ($key in (Get-SevenSegmentMap -Char $Char)) {
        $p = $points[$key]
        $line = New-Object System.Windows.Shapes.Line
        $line.X1 = $p[0]; $line.Y1 = $p[1]; $line.X2 = $p[2]; $line.Y2 = $p[3]
        $line.Stroke = $brush
        $line.StrokeThickness = $thickness
        $line.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
        $line.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
        [void]$canvas.Children.Add($line)
    }

    return $canvas
}

function New-SevenSegmentTimer {
    param(
        [string] $Text,
        [double] $Height = 32,
        [string] $Color = '#FF9F1C',
        [string] $GhostColor = ''
    )

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $spacing = [int][Math]::Ceiling($Height * 0.10)

    foreach ($char in $Text.ToCharArray()) {
        $element = New-SevenSegmentChar -Char $char -Height $Height -Color $Color -GhostColor $GhostColor
        $element.Margin = New-Object System.Windows.Thickness(0, 0, $spacing, 0)
        [void]$panel.Children.Add($element)
    }

    return $panel
}
