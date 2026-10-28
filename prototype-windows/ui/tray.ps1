<#
.SYNOPSIS    트레이 아이콘(고래)과 우클릭 메뉴를 관리한다.
.DESCRIPTION 상태에 따라 초록/빨강 아이콘을 교체하고 툴팁을 갱신한다. 메뉴는 새로고침,
             표시 모드(항상/피크만), 위치 초기화, 숨기기/보이기, 종료를 제공한다.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §3.2 (트레이)
.INPUTS      Icons(색→ico 경로), 각 동작 scriptblock
.OUTPUTS     트레이 객체 { Icon, Icons, Current, Menu }
.SIDE-EFFECTS 트레이 아이콘 상주, 메뉴 이벤트 등록.
.TESTS       수동 스모크(core.ps1 실행)
.NOTES       NotifyIcon 은 UI 스레드(STA)에서 생성해야 한다. Text 는 63자 제한.
#>

#region INDEX
#   New-NotifyTray  아이콘 + 메뉴 구성
#   Set-TrayState   severity 에 맞춰 아이콘·툴팁 갱신
#endregion

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
        [bool] $NotifyEnabled = $true,
        [string] $DisplayMode = 'always',
        [scriptblock] $OnToggleOled,
        [bool] $OledEnabled = $false,
        [bool] $CardVisible = $true
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
            Notify   = $notifyItem
            Oled     = $oledItem
            Always   = $alwaysItem
            PeakOnly = $peakItem
            Card     = $toggleItem
        }
    }
}

function Set-TrayChecks {
    param(
        [object] $Tray,
        [bool] $NotifyEnabled,
        [string] $DisplayMode,
        [bool] $OledEnabled = $false,
        [bool] $CardVisible = $true
    )

    if ($null -eq $Tray -or $null -eq $Tray.Items) { return }
    $Tray.Items.Notify.Checked = $NotifyEnabled
    if ($null -ne $Tray.Items.Oled) { $Tray.Items.Oled.Checked = $OledEnabled }
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
