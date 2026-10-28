<#
.SYNOPSIS    딥시크 로고를색으로 입혀 트레이용 ICO(멀티 사이즈)로 만든다.
.DESCRIPTION 원본 PNG(96px)의 알파를 유지한 채 RGB만 목표 색으로 바꾸고,
             16/20/24/32/48/256 크기로 리샘플해 PNG-in-ICO 컨테이너로 묶는다.
             GDI+ 와 System.Drawing 만 사용하며 외부 도구에 의존하지 않는다.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §3.2 (트레이 아이콘 색)
.INPUTS      SourcePath(로고 PNG), OutDir, Colors(이름→#RRGGBB), Sizes
.OUTPUTS     <name>.ico 4개 + preview.png (64px 견본 스트립)
.SIDE-EFFECTS 출력 디렉터리 생성·파일 쓰기.
.TESTS       tests\icons.ps1 T1-T4
.NOTES       로고는 DeepSeek 상표. 개인 로컬 트레이 표시 용도로만 쓰고 재배포하지 않는다.
             16px 가독성을 위해 MinimumAlpha 로 흐린 가장자리를 살짝 올린다.
#>

#region INDEX
#   New-TintedBitmap   알파 유지 + RGB 치환 (+최소 알파·외곽 1px 확장)
#   Resize-Bitmap      고품질 축소, 32bpp ARGB
#   Write-IcoFile      PNG-in-ICO 컨테이너 작성
#   Build-NotifyIcons  로고 → 4색 ICO + 미리보기
#endregion

Add-Type -AssemblyName System.Drawing

function New-TintedBitmap {
    param(
        [System.Drawing.Bitmap] $Source,
        [System.Drawing.Color]  $Color,
        [int]  $MinimumAlpha = 0,
        [switch] $Dilate,
        [int]  $DilateAlpha = 170
    )

    $width = $Source.Width
    $height = $Source.Height
    $tinted = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            $pixel = $Source.GetPixel($x, $y)
            if ($pixel.A -le 8) { continue }

            $alpha = [Math]::Max([int]$pixel.A, $MinimumAlpha)
            $alpha = [Math]::Min($alpha, 255)
            $tinted.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $Color.R, $Color.G, $Color.B))
        }
    }

    if (-not $Dilate) { return $tinted }

    $out = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            $pixel = $tinted.GetPixel($x, $y)
            if ($pixel.A -gt 32) { $out.SetPixel($x, $y, $pixel); continue }

            $neighbor = $false
            for ($dy = -1; $dy -le 1; $dy++) {
                for ($dx = -1; $dx -le 1; $dx++) {
                    $nx = $x + $dx; $ny = $y + $dy
                    if ($nx -lt 0 -or $nx -ge $width -or $ny -lt 0 -or $ny -ge $height) { continue }
                    if ($tinted.GetPixel($nx, $ny).A -gt 64) { $neighbor = $true }
                }
            }
            if ($neighbor) { $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($DilateAlpha, $Color.R, $Color.G, $Color.B)) }
        }
    }

    $tinted.Dispose()
    return $out
}

function Resize-Bitmap {
    param(
        [System.Drawing.Bitmap] $Source,
        [int] $Width,
        [int] $Height
    )

    $out = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($out)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.DrawImage($Source, 0, 0, $Width, $Height)
    $graphics.Dispose()

    return $out
}

function Write-IcoFile {
    param(
        [string[]] $PngPaths,
        [int[]]    $Sizes,
        [string]   $Path
    )

    $frames = @()
    for ($i = 0; $i -lt $PngPaths.Count; $i++) {
        $frames += [pscustomobject]@{
            Size  = $Sizes[$i]
            Bytes = [System.IO.File]::ReadAllBytes($PngPaths[$i])
        }
    }

    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)

    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$frames.Count)

    $offset = 6 + (16 * $frames.Count)
    foreach ($frame in $frames) {
        $dim = if ($frame.Size -ge 256) { 0 } else { $frame.Size }
        $writer.Write([byte]$dim)
        $writer.Write([byte]$dim)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length)
        $writer.Write([uint32]$offset)
        $offset += $frame.Bytes.Length
    }

    foreach ($frame in $frames) { $writer.Write($frame.Bytes) }

    $writer.Flush()
    [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
    $writer.Dispose()
    $stream.Dispose()
}

function Build-NotifyIcons {
    param(
        [string] $SourcePath,
        [string] $OutDir,
        [System.Collections.IDictionary] $Colors,
        [int[]]  $Sizes = @(16, 20, 24, 32, 48, 256)
    )

    if ($null -eq $Colors -or $Colors.Count -eq 0) {
        # 현재 provider(deepseek-peak)는 ok/alert 두 상태만 낸다. warn·unknown 생산자가 생기면
        # 여기에 'amber'/'gray' 를 추가하고 다시 생성하면 된다.
        $Colors = [ordered]@{
            'green' = '#1E7B3C'
            'red'   = '#B3261E'
        }
    }

    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }

    $source = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $SourcePath).Path)
    $tempDir = Join-Path $env:TEMP ('dsh-ico-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $preview = New-Object System.Drawing.Bitmap(($Colors.Count * 72), 72, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $previewGraphics = [System.Drawing.Graphics]::FromImage($preview)
    $previewGraphics.Clear([System.Drawing.Color]::FromArgb(255, 32, 32, 32))
    $previewGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    try {
        $index = 0
        foreach ($name in $Colors.Keys) {
            $color = [System.Drawing.ColorTranslator]::FromHtml($Colors[$name])
            $tinted = New-TintedBitmap -Source $source -Color $color -MinimumAlpha 220 -Dilate -DilateAlpha 190

            $pngPaths = @()
            foreach ($size in $Sizes) {
                $scaled = Resize-Bitmap -Source $tinted -Width $size -Height $size
                $pngPath = Join-Path $tempDir "$name-$size.png"
                $scaled.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $pngPaths += $pngPath

                if ($size -eq 256) {
                    $previewGraphics.DrawImage($scaled, ($index * 72 + 4), 4, 64, 64)
                }
                $scaled.Dispose()
            }

            Write-IcoFile -PngPaths $pngPaths -Sizes $Sizes -Path (Join-Path $OutDir "deepseek-$name.ico")
            $tinted.Dispose()
            $index++
        }

        $preview.Save((Join-Path $OutDir 'preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $previewGraphics.Dispose()
        $preview.Dispose()
        $source.Dispose()
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
