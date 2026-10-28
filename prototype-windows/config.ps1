<#
.SYNOPSIS    상주 앱 설정(config.json) 로드·저장과 표시 보조 계산.
.DESCRIPTION 기본값을 정의하고 기존 파일과 병합한다. 손상된 JSON 은 기본값+경고로 강등한다.
             저장은 temp 파일 후 교체로 원자적으로 한다. 화면 밖 좌표는 기본값으로 되돌리고,
             현지 시간 줄(해외 접속 시)을 만든다.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §4 (설정), §3.1 (현지 줄)
.INPUTS      Path, Config, X/Y/Bounds, UtcNow/NextChangeAt/TimeZone
.OUTPUTS     설정 객체 / 저장 / {X,Y} / '현지 18:00–21:00 (UTC-7)' 문자열
.SIDE-EFFECTS Save-NotifyConfig 는 파일 쓰기.
.TESTS       tests\core-config.ps1 C1-C6
.NOTES       displayMode: always | peakOnly. peakOnly 는 오프피크에 카드를 숨긴다.
#>

#region INDEX
#   Test-NotifyDirectoryWritable  저장 가능한 디렉터리인지 확인
#   Get-NotifyDataRoot            앱 루트 또는 %LOCALAPPDATA%\DSH-Notify
#   Get-NotifyFontRoot            앱 fonts 또는 데이터 fonts 폴백
#   Get-ConfigValue     StrictMode 안전한 속성 읽기
#   Get-NotifyConfig    기본값 + 파일 병합 (손상 시 경고)
#   Save-NotifyConfig   원자적 저장 (temp → 교체)
#   Get-ClampedPosition 화면 밖 좌표 → 기본 위치
#   Format-RegionWindow 현지 시간 범위 + UTC 오프셋
#endregion

Add-Type -AssemblyName System.Drawing

function Test-NotifyDirectoryWritable {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
        $probe = Join-Path $Path ('.write-probe-' + [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $probe -Value 'ok' -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

function Get-NotifyDataRoot {
    param([string] $AppRoot = $PSScriptRoot)

    if (-not [string]::IsNullOrWhiteSpace($env:DSH_NOTIFY_HOME)) {
        $override = $env:DSH_NOTIFY_HOME
        if (Test-NotifyDirectoryWritable -Path $override) { return (Resolve-Path -LiteralPath $override).Path }
    }

    if (Test-NotifyDirectoryWritable -Path $AppRoot) { return (Resolve-Path -LiteralPath $AppRoot).Path }

    $base = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DSH-Notify'
    if (-not (Test-NotifyDirectoryWritable -Path $base)) { throw "쓰기 가능한 데이터 경로를 만들 수 없습니다: $base" }
    return (Resolve-Path -LiteralPath $base).Path
}

function Get-NotifyFontRoot {
    param(
        [string] $AppRoot = $PSScriptRoot,
        [string] $DataRoot = ''
    )

    $appFonts = Join-Path $AppRoot 'fonts'
    if (Test-NotifyDirectoryWritable -Path $appFonts) { return (Resolve-Path -LiteralPath $appFonts).Path }

    # App root may be writable while its fonts child has a restrictive ACL.
    # Never throw just because the preferred folder is unavailable; use LocalAppData.
    if ([string]::IsNullOrWhiteSpace($DataRoot)) { $DataRoot = Get-NotifyDataRoot -AppRoot $AppRoot }
    if ([System.IO.Path]::GetFullPath($DataRoot) -eq [System.IO.Path]::GetFullPath($AppRoot)) {
        $DataRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DSH-Notify'
    }
    $dataFonts = Join-Path $DataRoot 'fonts'
    if (-not (Test-NotifyDirectoryWritable -Path $dataFonts)) { throw "쓰기 가능한 폰트 경로를 만들 수 없습니다: $dataFonts" }
    return (Resolve-Path -LiteralPath $dataFonts).Path
}

function Get-ConfigValue {
    param([object] $Object, [string] $Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-NotifyConfig {
    param([string] $Path)

    $config = [pscustomobject]@{
        DisplayMode    = 'always'
        Opacity        = 0.62
        PositionX      = 40
        PositionY      = 40
        NotifyOnChange = $true
        Notifications  = $true
        OledProtection = $false
        OledIntervalSeconds = 60
        PollSeconds    = 60
        ProviderConfig = @{ enabled = $true; treatMakeupAsPeak = $true; refreshHours = 240 }
        Warning        = ''
    }

    if (-not (Test-Path -LiteralPath $Path)) { return $config }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $config.Warning = '설정 파일이 손상되어 기본값을 사용합니다.'
        return $config
    }

    $mode = Get-ConfigValue -Object $raw -Name 'displayMode'
    if ($null -ne $mode -and "$mode" -in @('always', 'peakOnly')) { $config.DisplayMode = "$mode" }

    $opacity = Get-ConfigValue -Object $raw -Name 'opacity'
    if ($null -ne $opacity) { $config.Opacity = [Math]::Min(1.0, [Math]::Max(0.2, [double]$opacity)) }

    $position = Get-ConfigValue -Object $raw -Name 'position'
    if ($null -ne $position) {
        $x = Get-ConfigValue -Object $position -Name 'x'
        $y = Get-ConfigValue -Object $position -Name 'y'
        if ($null -ne $x) { $config.PositionX = [int]$x }
        if ($null -ne $y) { $config.PositionY = [int]$y }
    }

    $notifyOnChange = Get-ConfigValue -Object $raw -Name 'notifyOnChange'
    if ($null -ne $notifyOnChange) { $config.NotifyOnChange = [bool]$notifyOnChange }

    $notifications = Get-ConfigValue -Object $raw -Name 'notifications'
    if ($null -ne $notifications) { $config.Notifications = [bool]$notifications }

    $oled = Get-ConfigValue -Object $raw -Name 'oledProtection'
    if ($null -ne $oled) { $config.OledProtection = [bool]$oled }

    $oledInterval = Get-ConfigValue -Object $raw -Name 'oledIntervalSeconds'
    if ($null -ne $oledInterval) { $config.OledIntervalSeconds = [Math]::Max(5, [int]$oledInterval) }

    $pollSeconds = Get-ConfigValue -Object $raw -Name 'pollSeconds'
    if ($null -ne $pollSeconds) { $config.PollSeconds = [Math]::Max(10, [int]$pollSeconds) }

    $providers = Get-ConfigValue -Object $raw -Name 'providers'
    $provider = Get-ConfigValue -Object $providers -Name 'deepseek-peak'
    if ($null -ne $provider) {
        $enabled = Get-ConfigValue -Object $provider -Name 'enabled'
        $makeup = Get-ConfigValue -Object $provider -Name 'treatMakeupAsPeak'
        $refresh = Get-ConfigValue -Object $provider -Name 'refreshHours'
        if ($null -ne $enabled) { $config.ProviderConfig['enabled'] = [bool]$enabled }
        if ($null -ne $makeup) { $config.ProviderConfig['treatMakeupAsPeak'] = [bool]$makeup }
        if ($null -ne $refresh) { $config.ProviderConfig['refreshHours'] = [int]$refresh }
    }

    return $config
}

function Save-NotifyConfig {
    param([string] $Path, [object] $Config)

    $payload = [ordered]@{
        displayMode    = $Config.DisplayMode
        opacity        = $Config.Opacity
        position       = @{ x = $Config.PositionX; y = $Config.PositionY }
        notifyOnChange = $Config.NotifyOnChange
        notifications  = $Config.Notifications
        oledProtection = $Config.OledProtection
        oledIntervalSeconds = $Config.OledIntervalSeconds
        pollSeconds    = $Config.PollSeconds
        providers      = @{
            'deepseek-peak' = @{
                enabled           = $Config.ProviderConfig['enabled']
                treatMakeupAsPeak = $Config.ProviderConfig['treatMakeupAsPeak']
                refreshHours      = $Config.ProviderConfig['refreshHours']
            }
        }
    }

    $json = $payload | ConvertTo-Json -Depth 6
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $temp = "$Path.tmp"
    Set-Content -LiteralPath $temp -Value $json -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Get-ClampedPosition {
    param(
        [int] $X,
        [int] $Y,
        [System.Drawing.Rectangle] $Bounds,
        [int] $DefaultX = 40,
        [int] $DefaultY = 40
    )

    if ($X -lt $Bounds.Left -or $X -gt ($Bounds.Right - 80) -or $Y -lt $Bounds.Top -or $Y -gt ($Bounds.Bottom - 40)) {
        return [pscustomobject]@{ X = $DefaultX; Y = $DefaultY }
    }
    return [pscustomobject]@{ X = $X; Y = $Y }
}

function Format-RegionWindow {
    param(
        [datetime] $UtcNow,
        [datetime] $NextChangeAt,
        [System.TimeZoneInfo] $TimeZone
    )

    $start = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::SpecifyKind($UtcNow, 'Utc'), $TimeZone)
    $end = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::SpecifyKind($NextChangeAt, 'Utc'), $TimeZone)

    $offset = $TimeZone.GetUtcOffset($start)
    $sign = if ($offset.Ticks -lt 0) { '-' } else { '+' }
    $abs = $offset.Duration()
    $offsetText = if ($abs.Minutes -eq 0) {
        "UTC$sign$([int]$abs.TotalHours)"
    }
    else {
        "UTC$sign$([int]$abs.TotalHours):$('{0:00}' -f $abs.Minutes)"
    }

    return "Local $($start.ToString('HH:mm'))–$($end.ToString('HH:mm')) ($offsetText)"
}
