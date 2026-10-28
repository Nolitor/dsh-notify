<#
.SYNOPSIS    워드마크가 섞인 로고 소스에서 심볼(고래)만 잘라 정사각 마스크로 만든다.
.DESCRIPTION 알파>임계값 픽셀의 연결요소를 라벨링해 가장 큰 덩어리(심볼)를 찾고,
             그 덩어리의 바운딩박스만 잘라 여백을 둔 정사각 캔버스에 배치한다.
             바운딩박스 안에 다른 요소(예: 이웃 글자)가 걸쳐 있어도 라벨이 다르면 제외한다.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §3.2 (아이콘 자산)
.INPUTS      Bitmap, AlphaThreshold(기본 16), MinArea(기본 64), MarginRatio(기본 0.05)
.OUTPUTS     [pscustomobject] 바운딩박스+라벨 / 정사각 ARGB Bitmap
.SIDE-EFFECTS 없음 (메모리만).
.TESTS       tests\logo-mask.ps1 L1-L4
.NOTES       LockBits 로 픽셀을 일괄 처리한다. 심볼이 x=0/y=0 에 붙어 있으면 원본이 타이트 크롭된 것.
#>

#region INDEX
#   Get-InkComponentBounds     최대 연결요소(심볼) 바운딩박스 + 라벨맵
#   Get-ComponentMaskBitmap    선택한 라벨만 남긴 비트맵 (다른 요소 제거)
#   Get-LogoGlyph              심볼 크롭 + 정사각 패딩 캔버스
#endregion

Add-Type -AssemblyName System.Drawing

function Get-InkComponentBounds {
    param(
        [System.Drawing.Bitmap] $Bitmap,
        [int] $AlphaThreshold = 16,
        [int] $MinArea = 64
    )

    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $rect = New-Object System.Drawing.Rectangle 0, 0, $width, $height
    $locked = $Bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $locked.Stride
    $bytes = New-Object byte[] ($stride * $height)
    [System.Runtime.InteropServices.Marshal]::Copy($locked.Scan0, $bytes, 0, $bytes.Length)
    $Bitmap.UnlockBits($locked)

    # 0 = 미방문, -1 = 배경, 1..N = 컴포넌트
    $labels = New-Object int[] ($width * $height)
    $stack = New-Object int[] ($width * $height)
    $best = $null
    $bestLabel = 0
    $label = 0

    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            $index = ($y * $width) + $x
            if ($labels[$index] -ne 0) { continue }

            $alpha = $bytes[($y * $stride) + ($x * 4) + 3]
            if ($alpha -le $AlphaThreshold) { $labels[$index] = -1; continue }

            $label++
            $sp = 0
            $stack[$sp] = $index; $sp++
            $labels[$index] = $label

            $area = 0
            $minX = $x; $maxX = $x; $minY = $y; $maxY = $y

            while ($sp -gt 0) {
                $sp--
                $current = $stack[$sp]
                $cx = $current % $width
                $cy = [int][Math]::Floor($current / $width)
                $area++

                if ($cx -lt $minX) { $minX = $cx }
                if ($cx -gt $maxX) { $maxX = $cx }
                if ($cy -lt $minY) { $minY = $cy }
                if ($cy -gt $maxY) { $maxY = $cy }

                foreach ($offset in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))) {
                    $nx = $cx + $offset[0]
                    $ny = $cy + $offset[1]
                    if ($nx -lt 0 -or $nx -ge $width -or $ny -lt 0 -or $ny -ge $height) { continue }

                    $neighbor = ($ny * $width) + $nx
                    if ($labels[$neighbor] -ne 0) { continue }
                    if ($bytes[($ny * $stride) + ($nx * 4) + 3] -le $AlphaThreshold) {
                        $labels[$neighbor] = -1
                        continue
                    }

                    $labels[$neighbor] = $label
                    $stack[$sp] = $neighbor; $sp++
                }
            }

            if ($area -ge $MinArea -and ($null -eq $best -or $area -gt $best.Area)) {
                $best = [pscustomobject]@{
                    X      = $minX
                    Y      = $minY
                    Width  = ($maxX - $minX + 1)
                    Height = ($maxY - $minY + 1)
                    Area   = $area
                }
                $bestLabel = $label
            }
        }
    }

    if ($null -eq $best) { throw "잉크 픽셀(알파>$AlphaThreshold)을 찾지 못했습니다." }

    return [pscustomobject]@{
        X        = $best.X
        Y        = $best.Y
        Width    = $best.Width
        Height   = $best.Height
        Area     = $best.Area
        Label    = $bestLabel
        Labels   = $labels
        ImageWidth  = $width
        ImageHeight = $height
    }
}

function Get-ComponentMaskBitmap {
    param(
        [System.Drawing.Bitmap] $Source,
        [int[]] $Labels,
        [int]   $Label
    )

    $width = $Source.Width
    $height = $Source.Height
    $rect = New-Object System.Drawing.Rectangle 0, 0, $width, $height

    $sourceData = $Source.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $sourceStride = $sourceData.Stride
    $sourceBytes = New-Object byte[] ($sourceStride * $height)
    [System.Runtime.InteropServices.Marshal]::Copy($sourceData.Scan0, $sourceBytes, 0, $sourceBytes.Length)
    $Source.UnlockBits($sourceData)

    $masked = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $destData = $masked.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $destStride = $destData.Stride
    $destBytes = New-Object byte[] ($destStride * $height)

    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            if ($Labels[($y * $width) + $x] -ne $Label) { continue }
            $si = ($y * $sourceStride) + ($x * 4)
            $di = ($y * $destStride) + ($x * 4)
            $destBytes[$di] = $sourceBytes[$si]
            $destBytes[$di + 1] = $sourceBytes[$si + 1]
            $destBytes[$di + 2] = $sourceBytes[$si + 2]
            $destBytes[$di + 3] = $sourceBytes[$si + 3]
        }
    }

    [System.Runtime.InteropServices.Marshal]::Copy($destBytes, 0, $destData.Scan0, $destBytes.Length)
    $masked.UnlockBits($destData)

    return $masked
}

function Get-LogoGlyph {
    param(
        [System.Drawing.Bitmap] $Source,
        [double] $MarginRatio = 0.05,
        [int]    $AlphaThreshold = 16
    )

    $bounds = Get-InkComponentBounds -Bitmap $Source -AlphaThreshold $AlphaThreshold
    $masked = Get-ComponentMaskBitmap -Source $Source -Labels $bounds.Labels -Label $bounds.Label

    $side = [int][Math]::Ceiling([Math]::Max($bounds.Width, $bounds.Height) * (1 + (2 * $MarginRatio)))
    $canvas = New-Object System.Drawing.Bitmap($side, $side, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $dx = [int][Math]::Floor(($side - $bounds.Width) / 2)
    $dy = [int][Math]::Floor(($side - $bounds.Height) / 2)

    $sourceRect = New-Object System.Drawing.Rectangle($bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
    $destRect = New-Object System.Drawing.Rectangle($dx, $dy, $bounds.Width, $bounds.Height)
    $graphics.DrawImage($masked, $destRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
    $graphics.Dispose()
    $masked.Dispose()

    return $canvas
}
