<#
.SYNOPSIS    시작 메뉴에 DSH Notify 바로가기를 만든다 (콘솔 없이 실행).
.DESCRIPTION pwsh.exe 를 -Sta/숨김으로 실행해 core.ps1 을 띄우는 .lnk 를 만든다.
             VBScript 가 없어도 되고, exe 서명/정책 문제도 없다. 트레이 아이콘을 그대로 쓴다.
.CONTRACT    core.ps1
.INPUTS      -Name(기본 DSH Notify), -StartMenu(기본 사용자 프로그램 폴더)
.OUTPUTS     .lnk 경로
.SIDE-EFFECTS 시작 메뉴에 파일 생성/덮어쓰기.
.TESTS       수동: 바로가기 실행 후 프로세스 확인
.NOTES       Smart App Control 이 켜진 PC 는 서명 없는 exe 를 막으므로 이 방식이 실용적이다.
#>

#region INDEX
#   (main)  경로 확인 → WScript.Shell 로 .lnk 생성
#endregion

param(
    [string] $Name = 'DSH Notify',
    [string] $StartMenu = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$core = Join-Path $repoRoot 'core.ps1'
$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
$icon = Join-Path $repoRoot 'ui\icons\deepseek-green.ico'

if (-not (Test-Path -LiteralPath $core)) { throw "core.ps1 없음: $core" }
if ([string]::IsNullOrWhiteSpace($pwsh)) { throw 'pwsh.exe 를 찾지 못했습니다.' }
if ([string]::IsNullOrWhiteSpace($StartMenu)) {
    $StartMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
}

$linkPath = Join-Path $StartMenu "$Name.lnk"
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$link.TargetPath = $pwsh
$link.Arguments = "-Sta -NoProfile -WindowStyle Hidden -File `"$core`""
$link.WorkingDirectory = $repoRoot
$link.WindowStyle = 7
$link.Description = 'DeepSeek 피크 구간 인디케이터'
if (Test-Path -LiteralPath $icon) { $link.IconLocation = "$icon,0" }
$link.Save()

Write-Host "OK: $linkPath"
exit 0
