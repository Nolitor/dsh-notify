<#
.SYNOPSIS    provider 상태를 인디케이터 창/트레이가 그릴 수 있는 표시 모델로 변환한다.
.DESCRIPTION 판정·알림 로직과 무관하게 순수 변환만 한다. 색·문구·표시여부·남은시간을 결정하고,
             전환 알림 여부는 별도 함수로 분리해 테스트한다.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §2.3 severity 매핑, §3.1 표시 모드
.INPUTS      State(Get-State 결과), Config(displayMode·opacity), Now, LocalLine(선택)
.OUTPUTS     Visible, Severity, Background, Opacity, Headline, Detail, LocalLine, TrayIcon
.SIDE-EFFECTS 없음 (순수).
.TESTS       tests\presenter.ps1 P1-P8
.NOTES       Detail 은 매 틱(30초) 재계산 가능하도록 NextChangeAt 기반으로 만든다.
#>

#region INDEX
#   Format-PeakRemaining   남은 시간 → '2h 00m' / '42m' / '곧 구간 전환'
#   Format-PeakTimer       남은 시간 → '02:14' (7세그 타이머용)
#   Get-IndicatorTitle     'DeepSeek 피크 (100%)' — 소문자 문장, 중점 없음
#   Get-IndicatorDetail    '→ 다음 구간까지 …' + 추정 배지 (툴팁용)
#   Get-IndicatorView      상태+설정 → 표시 모델 (색·표시여부·타이머·트레이 아이콘)
#   Test-NotifyTransition  severity 전환 시 1회 알림 여부 (시작 직후 억제)
#endregion

function Format-PeakRemaining {
    param([object] $NextChangeAt, [datetime] $Now)

    if ($null -eq $NextChangeAt) { return '알 수 없음' }

    $delta = (ConvertTo-ContractUtc -Value ([datetime]$NextChangeAt)) - (ConvertTo-ContractUtc -Value $Now)
    $minutes = [int][Math]::Floor($delta.TotalMinutes)
    if ($minutes -le 1) { return '곧 구간 전환' }

    $hours = [int][Math]::Floor($minutes / 60)
    $rest = $minutes % 60
    if ($hours -gt 0) { return "${hours}h $('{0:00}' -f $rest)m" }
    return "${rest}m"
}

function Get-IndicatorDetail {
    param([object] $State, [datetime] $Now)

    $badge = ''
    if ("$($State.Detail)" -like '*(추정*') { $badge = ' (추정)' }

    return '→ 다음 구간까지 ' + (Format-PeakRemaining -NextChangeAt $State.NextChangeAt -Now $Now) + $badge
}

function Get-IndicatorTitle {
    param([object] $State, [string] $Severity)

    $percent = ''
    if ("$($State.Headline)" -match '(\d+)%') { $percent = $Matches[1] + '%' }

    $label = if ($Severity -eq 'alert') { 'Peak' } elseif ($Severity -eq 'warn') { 'Warning' } else { 'Off-Peak' }
    if ([string]::IsNullOrEmpty($percent)) { return "DeepSeek $label" }
    if ($Severity -ne 'alert') { return "DeepSeek $label ($percent discount)" }
    return "DeepSeek $label ($percent)"
}

function ConvertTo-ContractUtc {
    param([datetime] $Value)

    if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value }
    if ($Value.Kind -eq [System.DateTimeKind]::Local) { return $Value.ToUniversalTime() }
    return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
}

function Get-TimerParts {
    param([object] $NextChangeAt, [datetime] $Now)

    if ($null -eq $NextChangeAt) {
        return [pscustomobject]@{ Main = '--:--'; Dim = ':--' }
    }

    $nextUtc = ConvertTo-ContractUtc -Value ([datetime]$NextChangeAt)
    $nowUtc = ConvertTo-ContractUtc -Value $Now
    $total = [int][Math]::Floor(($nextUtc - $nowUtc).TotalSeconds)
    if ($total -lt 0) { $total = 0 }

    $hours = [int][Math]::Floor($total / 3600)
    $minutes = [int][Math]::Floor(($total % 3600) / 60)
    $seconds = $total % 60

    return [pscustomobject]@{
        Main = ('{0:00}:{1:00}' -f $hours, $minutes)
        Dim  = (':{0:00}' -f $seconds)
    }
}

function Format-PeakTimer {
    param([object] $NextChangeAt, [datetime] $Now)

    $parts = Get-TimerParts -NextChangeAt $NextChangeAt -Now $Now
    return "$($parts.Main)$($parts.Dim)"
}

function Get-IndicatorView {
    param(
        [object]   $State,
        [hashtable] $Config,
        [datetime] $Now,
        [string]   $LocalLine = ''
    )

    $mode = if ($null -ne $Config -and $Config.ContainsKey('displayMode')) { "$($Config['displayMode'])" } else { 'always' }
    $opacity = if ($null -ne $Config -and $Config.ContainsKey('opacity')) { [double]$Config['opacity'] } else { 0.62 }
    $severity = "$($State.Severity)"
    $isAlert = $severity -eq 'alert'

    $visible = if ($mode -eq 'peakOnly') { $severity -in @('alert', 'warn') } else { $true }

    $parts = Get-TimerParts -NextChangeAt $State.NextChangeAt -Now $Now

    return [pscustomobject]@{
        Visible    = $visible
        Severity   = $severity
        Background = if ($isAlert) { '#B3261E' } else { '#1E7B3C' }
        Opacity    = $opacity
        Title      = Get-IndicatorTitle -State $State -Severity $severity
        TimerText  = "$($parts.Main)$($parts.Dim)"
        TimerMain  = $parts.Main
        TimerDim   = $parts.Dim
        TimerColor = if ($isAlert) { '#E5534B' } else { '#4ADE80' }
        Headline   = $State.Headline
        Detail     = Get-IndicatorDetail -State $State -Now $Now
        LocalLine  = $LocalLine
        TrayIcon   = if ($isAlert) { 'deepseek-red' } else { 'deepseek-green' }
    }
}

function Test-NotifyTransition {
    param(
        [string] $PreviousSeverity,
        [string] $CurrentSeverity,
        [bool]   $NotifyOnChange = $true
    )

    if (-not $NotifyOnChange) { return $false }
    if ([string]::IsNullOrEmpty($PreviousSeverity)) { return $false }  # 앱 시작 직후 첫 관측은 억제
    return $PreviousSeverity -ne $CurrentSeverity
}
