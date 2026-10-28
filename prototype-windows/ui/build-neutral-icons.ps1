<#
.SYNOPSIS    중립 시계 트레이 아이콘(초록/빨강)을 생성한다.
.DESCRIPTION DeepSeek 로고 대신 자체 제작한 시계 글리프를 32x32 ICO로 저장한다.
             공개 패키지에 상표 자산을 넣지 않기 위한 기본 아이콘이다.
.CONTRACT    app\tray.ps1, core.ps1
.INPUTS      -OutDir(기본 ui\icons)
.OUTPUTS     neutral-green.ico, neutral-red.ico
.SIDE-EFFECTS ICO 파일 생성/덮어쓰기.
.TESTS       수동: ui\build-neutral-icons.ps1 실행 후 ICO 로드
.NOTES       MIT. 외부 로고/폰트를 사용하지 않는다.
#>

#region INDEX
#   New-ClockIcon  색상별 시계 ICO 생성
#   (main)         green/red 두 파일 생성
#endregion

param([string] $OutDir = (Join-Path $PSScriptRoot 'icons'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-ClockIcon {
    param(
        [string] $Path,
        [System.Drawing.Color] $Color
    )

    $bitmap = New-Object System.Drawing.Bitmap(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $brush = New-Object System.Drawing.SolidBrush($Color)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.2)
        try {
            $graphics.FillEllipse($brush, 3, 3, 26, 26)
            $graphics.DrawLine($pen, 16, 16, 16, 8)
            $graphics.DrawLine($pen, 16, 16, 22, 19)
            $graphics.FillEllipse([System.Drawing.Brushes]::White, 14, 14, 4, 4)
        }
        finally {
            $pen.Dispose()
            $brush.Dispose()
        }
        $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
        try {
            $stream = [System.IO.File]::Create($Path)
            try { $icon.Save($stream) } finally { $stream.Dispose() }
        }
        finally {
            $icon.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
New-ClockIcon -Path (Join-Path $OutDir 'neutral-green.ico') -Color ([System.Drawing.Color]::FromArgb(255, 30, 123, 60))
New-ClockIcon -Path (Join-Path $OutDir 'neutral-red.ico') -Color ([System.Drawing.Color]::FromArgb(255, 229, 83, 75))
Write-Host "OK: $OutDir"
