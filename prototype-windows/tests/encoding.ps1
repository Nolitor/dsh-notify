<#
.SYNOPSIS    Windows PowerShell 5.1 이 실행하는 스크립트가 UTF-8 BOM 을 갖는지 검사한다.
.DESCRIPTION notify\*.ps1 은 토스트 표시를 위해 5.1 자식 프로세스가 직접 파싱한다.
             5.1 은 BOM 없는 UTF-8 을 ANSI 로 읽어 한글 리터럴이 깨진다(실측).
             그래서 이 디렉터리의 스크립트는 반드시 BOM 을 가져야 한다.
.CONTRACT    docs\dsh-harness-notify-spec.md §4 (표시·인코딩)
.INPUTS      없음. $PSScriptRoot 기준 notify\*.ps1 을 검사한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 BOM 보유, 1 = 위반 있음.
.SIDE-EFFECTS 없음 (읽기 전용).
.TESTS       이 파일 자체가 검사기다.
.NOTES       편집 도구가 BOM 을 떨어뜨리면 여기서 잡힌다.
#>

#region INDEX
#   Test-Bom    파일 선두 3바이트가 EF BB BF 인지 확인
#   (main)      notify\*.ps1 전수 검사
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$notifyDir = Join-Path $repoRoot 'notify'

function Test-Bom {
    param([string] $Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}

$files = @(Get-ChildItem -Path $notifyDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($files.Count -eq 0) {
    Write-Host 'FAIL encoding: notify\*.ps1 없음'
    exit 1
}

$fail = 0
foreach ($file in $files) {
    if (Test-Bom -Path $file.FullName) {
        Write-Host "PASS $($file.Name) UTF-8 BOM"
        continue
    }
    $fail++
    Write-Host "FAIL $($file.Name) — UTF-8 BOM 없음 (5.1 에서 한글이 깨진다)"
}

Write-Host ''
Write-Host "encoding: $($files.Count - $fail) passed / $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
