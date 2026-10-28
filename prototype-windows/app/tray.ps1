<#
.SYNOPSIS    트레이 아이콘과 우클릭 메뉴, '부팅 시 자동 실행' 토글을 관리한다.
.DESCRIPTION 상태에 따라 초록/빨강 아이콘을 교체하고 툴팁을 갱신한다. 메뉴는 새로고침,
             표시 모드, 위치 초기화, 숨기기/보이기, 부팅 시 자동 실행, 종료를 제공한다.
             자동 실행은 사용자 Startup 폴더의 .lnk만 생성/삭제하며 레지스트리를 건드리지 않는다.
.CONTRACT    config.ps1, core.ps1
.INPUTS      Icons(색→ico 경로), 각 동작 scriptblock, StartupDir/ShortcutName(테스트)
.OUTPUTS     트레이 객체 { Icon, Icons, Current, Menu, Items }
.SIDE-EFFECTS 트레이 아이콘 상주, 메뉴 이벤트 등록, Startup .lnk 생성/삭제.
.TESTS       tests\autostart.ps1, 수동 스모크(core.ps1)
.NOTES       NotifyIcon 은 UI 스레드(STA)에서 생성해야 한다. Text 는 63자 제한.
#>

#region INDEX
#   Get-NotifyStartupDir          사용자 Startup 폴더 (테스트 override)
#   Get-NotifyStartupShortcutPath Startup .lnk 경로
#   Test-NotifyAutostart          .lnk 존재 여부
#   Set-NotifyAutostart           .lnk 생성/삭제 (WScript.Shell, 무권한)
#   New-NotifyTray                아이콘 + 메뉴 구성
#   Set-TrayChecks                체크 상태 동기화
#   Set-TrayState                 severity 에 맞춰 아이콘·툴팁 갱신
#endregion

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-NotifyStartupDir {
    param([string] $StartupDir = '')

    if (-not [string]::IsNullOrWhiteSpace($StartupDir)) { return $StartupDir }
    return [Environment]::GetFolderPath('Startup')
}

function Get-NotifyStartupShortcutPath {
    param(
        [string] $StartupDir = '',
        [string] $Name = 'DSH Notify.lnk'
    )

    return Join-Path (Get-NotifyStartupDir -StartupDir $StartupDir) $Name
}

function Test-NotifyAutostart {
    param(
        [string] $StartupDir = '',
        [string] $Name = 'DSH Notify.lnk'
    )

    return Test-Path -LiteralPath (Get-NotifyStartupShortcutPath -StartupDir $StartupDir -Name $Name) -PathType Leaf
}

function Set-NotifyAutostart {
    param(
        [bool] $Enabled,
        [string] $StartupDir = '',
        [string] $Name = 'DSH Notify.lnk',
        [string] $AppRoot = (Split-Path -Parent $PSScriptRoot),
        [string] $StartCmd = '',
        [string] $IconPath = ''
    )

    $shortcutPath = Get-NotifyStartupShortcutPath -StartupDir $StartupDir -Name $Name
    $targetDir = Get-NotifyStartupDir -StartupDir $StartupDir
    if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

    if (-not $Enabled) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($StartCmd)) {
        $launch = Join-Path $AppRoot 'launch.js'
        $StartCmd = if (Test-Path -LiteralPath $launch -PathType Leaf) { $launch } else { Join-Path $AppRoot 'start.cmd' }
    }

    $target = ''
    $arguments = ''
    $extension = [System.IO.Path]::GetExtension($StartCmd).ToLowerInvariant()
    if ($extension -in @('.js', '.vbs', '.wsf')) {
        # Zero-flicker: wscript.exe is a GUI-subsystem host, no console is created.
        $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
        if (-not (Test-Path -LiteralPath $wscript -PathType Leaf)) { throw "wscript.exe 를 찾지 못했습니다: $wscript" }
        $target = $wscript
        $arguments = '//B //NoLogo "' + $StartCmd + '"'
    }
    elseif (Test-Path -LiteralPath $StartCmd -PathType Leaf) {
        $target = $StartCmd
    }
    else {
        $pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
        if ([string]::IsNullOrWhiteSpace($pwsh)) { throw 'pwsh.exe 를 찾지 못했습니다.' }
        $core = Join-Path $AppRoot 'core.ps1'
        if (-not (Test-Path -LiteralPath $core)) { throw "core.ps1 이 없습니다: $core" }
        $target = $pwsh
        $arguments = "-Sta -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$core`""
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $target
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $AppRoot
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'DSH Notify — DeepSeek off-peak widget'
    if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath)) {
        $shortcut.IconLocation = "$IconPath,0"
    }
    $shortcut.Save()

    return (Test-Path -LiteralPath $shortcutPath -PathType Leaf)
}

function New-NotifyTray {
    param(
        [hashtable] $Icons,
        [scriptblock] $OnRefresh,
        [scriptblock] $OnAlways,
        [scriptblock] $OnPeakOnly,
        [scriptblock] $OnReset,
        [scriptblock] $OnToggle,
        [scriptblock] $OnExit,
        [scriptblock] $OnToggleNotifications,
        [scriptblock] $OnToggleOled,
        [scriptblock] $OnToggleAutostart,
        [bool] $NotifyEnabled = $true,
        [string] $DisplayMode = 'always',
        [bool] $OledEnabled = $false,
        [bool] $AutostartEnabled = $false,
        [bool] $CardVisible = $true,
        [string] $StartupDir = '',
        [string] $ShortcutName = 'DSH Notify.lnk'
    )

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Icon = New-Object System.Drawing.Icon($Icons['green'])
    $notifyIcon.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    function Add-Entry([string] $label, [scriptblock] $action) {
        $item = New-Object System.Windows.Forms.ToolStripMenuItem($label)
        $item.Add_Click({ param($sender, $eventArgs) & $action }.GetNewClosure())
        [void]$menu.Items.Add($item)
        return $item
    }

    $refreshItem = Add-Entry '지금 갱신' $OnRefresh
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $notifyItem = Add-Entry '알림' $OnToggleNotifications
    $notifyItem.CheckOnClick = $true
    $notifyItem.Checked = $NotifyEnabled

    $oledItem = Add-Entry 'OLED 보호' $OnToggleOled
    $oledItem.CheckOnClick = $true
    $oledItem.Checked = $OledEnabled
    $oledItem.ToolTipText = '켜면 일정 간격으로 카드를 5px씩 움직여 번인을 줄입니다.'

    $autostartItem = Add-Entry '부팅 시 자동 실행' $OnToggleAutostart
    $autostartItem.CheckOnClick = $true
    $autostartItem.Checked = [bool]$AutostartEnabled
    $autostartItem.ToolTipText = '사용자 시작프로그램 폴더에 바로가기를 만들거나 제거합니다. 관리자 권한이 필요 없습니다.'

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $alwaysItem = Add-Entry '항상 표시' $OnAlways
    $peakItem = Add-Entry '피크일 때만' $OnPeakOnly

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $resetItem = Add-Entry '위치 초기화' $OnReset
    $toggleItem = Add-Entry '카드 보이기' $OnToggle
    $toggleItem.CheckOnClick = $true
    $toggleItem.Checked = $CardVisible
    $exitItem = Add-Entry '종료' $OnExit

    $notifyIcon.ContextMenuStrip = $menu
    $notifyIcon.Add_MouseDoubleClick({ param($sender, $eventArgs) & $OnToggle }.GetNewClosure())

    return [pscustomobject]@{
        Icon    = $notifyIcon
        Icons   = $Icons
        Current = 'green'
        Menu    = $menu
        Items   = [pscustomobject]@{
            Notify    = $notifyItem
            Oled      = $oledItem
            Autostart = $autostartItem
            Always    = $alwaysItem
            PeakOnly  = $peakItem
            Card      = $toggleItem
        }
        StartupDir   = $StartupDir
        ShortcutName = $ShortcutName
    }
}

function Set-TrayChecks {
    param(
        [object] $Tray,
        [bool] $NotifyEnabled,
        [string] $DisplayMode,
        [bool] $OledEnabled = $false,
        [bool] $AutostartEnabled = $false,
        [bool] $CardVisible = $true
    )

    if ($null -eq $Tray -or $null -eq $Tray.Items) { return }
    $Tray.Items.Notify.Checked = $NotifyEnabled
    if ($null -ne $Tray.Items.Oled) { $Tray.Items.Oled.Checked = $OledEnabled }
    if ($null -ne $Tray.Items.Autostart) { $Tray.Items.Autostart.Checked = $AutostartEnabled }
    $Tray.Items.Always.Checked = ($DisplayMode -eq 'always')
    $Tray.Items.PeakOnly.Checked = ($DisplayMode -eq 'peakOnly')
    if ($null -ne $Tray.Items.Card) { $Tray.Items.Card.Checked = $CardVisible }
}

function Set-TrayState {
    param(
        [object] $Tray,
        [object] $View,
        [string] $Tooltip
    )

    $name = if ("$($View.TrayIcon)" -like '*red*') { 'red' } else { 'green' }
    if ($Tray.Current -ne $name) {
        $Tray.Icon.Icon = New-Object System.Drawing.Icon($Tray.Icons[$name])
        $Tray.Current = $name
    }

    $text = $Tooltip
    if ([string]::IsNullOrWhiteSpace($text)) { $text = 'DSH Notify' }
    if ($text.Length -gt 62) { $text = $text.Substring(0, 62) }
    $Tray.Icon.Text = $text
}
