<#
.SYNOPSIS    인디케이터 카드를 화면 없이 PNG 로 렌더해 시각 검증에 쓴다 (STA 전용).
.DESCRIPTION presenter 로 가짜 상태의 표시 모델을 만들고, 어두운 배경 위에 카드를 합성해
             RenderTargetBitmap 으로 저장한다. 반투명(0.82)이 실제로 어떻게 보이는지 확인한다.
.CONTRACT    ui\indicator.ps1 — New-IndicatorVisual
.INPUTS      -Severity alert|ok, -Out 경로, -Scale(기본 2)
.OUTPUTS     PNG 파일, 콘솔에 크기
.SIDE-EFFECTS 파일 쓰기.
.TESTS       tests\indicator-render.ps1
.NOTES       반드시 pwsh -Sta 로 실행한다. 화면에 창을 띄우지 않는다.
#>

#region INDEX
#   (main)  가짜 상태 → 표시 모델 → 비주얼 → RenderTargetBitmap → PNG
#endregion

param(
    [ValidateSet('alert', 'ok')] [string] $Severity = 'alert',
    [string] $Out = (Join-Path $env:TEMP 'indicator-preview.png'),
    [double] $Scale = 2
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'ui\presenter.ps1')
. (Join-Path $repoRoot 'ui\indicator.ps1')

$now = Get-Date
$state = if ($Severity -eq 'alert') {
    [pscustomobject]@{
        Id = 'deepseek-peak'; Label = 'DeepSeek 과금'; Severity = 'alert'
        Headline = 'PEAK · 100%'
        Detail = '→ 다음 구간까지 2h 14m'
        NextChangeAt = $now.AddMinutes(134)
        NotifyText = ''
    }
}
else {
    [pscustomobject]@{
        Id = 'deepseek-peak'; Label = 'DeepSeek 과금'; Severity = 'ok'
        Headline = 'OFF-PEAK · 50%'
        Detail = '→ 다음 구간까지 1h 07m'
        NextChangeAt = $now.AddMinutes(67)
        NotifyText = ''
    }
}

$localLine = if ($Severity -eq 'alert') { 'Local 18:00–21:00 (UTC-7)' } else { '' }
$view = Get-IndicatorView -State $state -Config @{ displayMode = 'always'; opacity = 0.82 } -Now $now -LocalLine $localLine

$card = New-IndicatorCard -View $view
$cardScale = New-Object System.Windows.Media.ScaleTransform($Scale, $Scale)
$card.RenderTransform = $cardScale
$card.RenderTransformOrigin = New-Object System.Windows.Point(0, 0)

$pad = 20
$canvasWidth = [int](($card.Width * $Scale) + ($pad * 2))
$canvasHeight = [int](($card.Height * $Scale) + ($pad * 2))

$canvas = New-Object System.Windows.Controls.Grid
$canvas.Width = $canvasWidth
$canvas.Height = $canvasHeight
$canvas.Background = New-Object System.Windows.Media.SolidColorBrush(
    [System.Windows.Media.Color]::FromArgb(255, 32, 32, 32))
[void]$canvas.Children.Add($card)
[System.Windows.Controls.Canvas]::SetLeft($card, $pad)
[System.Windows.Controls.Canvas]::SetTop($card, $pad)
$card.Margin = New-Object System.Windows.Thickness($pad, $pad, 0, 0)
$card.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
$card.VerticalAlignment = [System.Windows.VerticalAlignment]::Top

$canvas.Measure([System.Windows.Size]::new($canvasWidth, $canvasHeight))
$canvas.Arrange([System.Windows.Rect]::new(0, 0, $canvasWidth, $canvasHeight))
$canvas.UpdateLayout()

$bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
    $canvasWidth, $canvasHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
$bitmap.Render($canvas)

$encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
$encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
$stream = [System.IO.File]::Create($Out)
try { $encoder.Save($stream) } finally { $stream.Dispose() }

Write-Host "OK: $canvasWidth x $canvasHeight -> $Out"
exit 0
