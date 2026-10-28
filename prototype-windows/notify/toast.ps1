<#
.SYNOPSIS    윈도 네이티브 토스트 알림 생성·표시 (Windows.UI.Notifications).
.DESCRIPTION 포트·웹서버 없이 Windows 10/11 토스트를 띄운다. XML 생성은 어느 PowerShell 에서나 가능하고,
             실제 표시는 WinRT 타입을 읽을 수 있는 Windows PowerShell 5.1 프로세스에서만 수행한다.
             PS7 에서 직접 호출하면 명확한 오류를 던진다 (notify\send-toast.ps1 이 5.1 로 위임).
.CONTRACT    docs\deepseek-peak-spec.md §4.4 (표시 계층), design §3.3 (알림)
.INPUTS      Title, Body, AppId (기본: Windows PowerShell AUMID)
.OUTPUTS     XML 문자열. 표시 성공 시에도 XML 반환.
.SIDE-EFFECTS 실제 호출 시 윈도 알림 표시. -DryRun 이면 표시하지 않음.
.TESTS       tests\toast.ps1 T1-T4 (XML), T5-T6 (CLI dry-run)
.NOTES       PS7 은 [Windows.UI.Notifications.*, ContentType=WindowsRuntime] 로드에 실패한다(실측).
             기본 AppId 는 "Windows PowerShell" 로 표시된다. 앱 이름·아이콘 브랜딩은
             시작메뉴 바로가기 + AUMID 등록이 필요하므로 v1 범위 밖.
#>

#region INDEX
#   New-ToastXml        ToastGeneric XML 생성 (텍스트 이스케이프는 XmlDocument 에 위임)
#   Send-WindowsToast   표시 — 5.1 프로세스 필요, PS7 은 오류
#endregion

$script:DefaultToastAppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

function New-ToastXml {
    param([string] $Title = 'DSH Notify', [string] $Body = '')

    $doc = New-Object System.Xml.XmlDocument
    $toast = $doc.CreateElement('toast')
    [void]$doc.AppendChild($toast)

    $visual = $doc.CreateElement('visual')
    [void]$toast.AppendChild($visual)

    $binding = $doc.CreateElement('binding')
    $binding.SetAttribute('template', 'ToastGeneric')
    [void]$visual.AppendChild($binding)

    foreach ($text in @($Title, $Body)) {
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $element = $doc.CreateElement('text')
        $element.InnerText = $text
        [void]$binding.AppendChild($element)
    }

    return $doc.OuterXml
}

function Send-WindowsToast {
    param(
        [string] $Title = 'DSH Notify',
        [string] $Body = '',
        [string] $AppId = $script:DefaultToastAppId,
        [switch] $DryRun
    )

    $xmlText = New-ToastXml -Title $Title -Body $Body
    if ($DryRun) { return $xmlText }

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        throw 'PS7 은 WinRT 토스트 타입을 직접 로드할 수 없다. notify\send-toast.ps1 을 호출해 5.1 자식 프로세스에서 표시한다.'
    }

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlText)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)

    return $xmlText
}
