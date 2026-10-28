<#
.SYNOPSIS    트레이 아이콘(4색)을 생성하는 CLI.
.DESCRIPTION ui\assets\deepseek-logo.png 를 읽어 ui\icons\ 에 ICO 4개와 미리보기를 만든다.
             로고 색이 바뀌면 이 스크립트만 다시 실행하면 된다.
.CONTRACT    ui\icons.ps1 — Build-NotifyIcons
.INPUTS      -Source(기본 assets), -OutDir(기본 icons)
.OUTPUTS     deepseek-green/red/amber/gray.ico, preview.png
.SIDE-EFFECTS ui\icons\ 파일 덮어쓰기.
.TESTS       tests\icons.ps1 T4 (함수 경로 검증)
.NOTES       한글 주석 유지(PS7 실행 전용, BOM 불필요).
#>

#region INDEX
#   (main)  로고 경로 확인 → Build-NotifyIcons 호출
#endregion

param(
    [string] $Source = (Join-Path $PSScriptRoot 'assets\deepseek-logo.png'),
    [string] $OutDir = (Join-Path $PSScriptRoot 'icons')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'icons.ps1')

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Host "FAIL: 로고 파일 없음 — $Source"
    exit 1
}

Build-NotifyIcons -SourcePath $Source -OutDir $OutDir
$icons = @(Get-ChildItem -Path $OutDir -Filter '*.ico' -File)
Write-Host "OK: $($icons.Count) icons -> $OutDir"
exit 0
