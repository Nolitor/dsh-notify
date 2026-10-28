<#
.SYNOPSIS    Windows Media Foundation(WinRT)으로 WAV 를 재생한다 — WinMM 이 막힌 환경용.
.DESCRIPTION 이 PC 에서 System.Media.SoundPlayer(WinMM) 는 스피커 앰프까지 소리가 도달하지 않는다.
             윈도 미디어 플레이어가 쓰는 것과 같은 Media Foundation 경로로 재생한다.
             Windows PowerShell 5.1 에서 실행해야 WinRT 타입을 로드할 수 있다.
.CONTRACT    docs\dsh-harness-notify-spec.md §4
.INPUTS      Path, Ms, Volume, Loop
.OUTPUTS     없음.
.SIDE-EFFECTS WAV 재생.
.TESTS       tests\popup-request.ps1 (존재/구문), 수동 스모크
.NOTES       PS7 은 WinRT 를 직접 로드하지 못한다 → core 가 powershell.exe 로 위임한다.
#>

#region INDEX
#   (main)  MediaPlayer 생성 → MediaSource 지정 → 재생 → Ms 후 정지
#endregion

param(
    [Parameter(Mandatory = $true)][string] $Path,
    [int] $Ms = 3000,
    [double] $Volume = 1.0,
    [switch] $Loop
)

$ErrorActionPreference = 'Stop'

[Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Core.MediaSource, Windows.Media.Core, ContentType = WindowsRuntime] | Out-Null

$player = New-Object Windows.Media.Playback.MediaPlayer
$player.Volume = $Volume
$player.IsLoopingEnabled = [bool]$Loop
$player.Source = [Windows.Media.Core.MediaSource]::CreateFromUri([Uri]$Path)
$player.Play()

Start-Sleep -Milliseconds ([Math]::Max(200, $Ms))
$player.Pause()
$player.Dispose()
