<#
.SYNOPSIS    우하단 커스텀 팝업의 기하·인자 계약을 검증한다.
.DESCRIPTION -DryRun 은 창을 띄우지 않고 제목/본문/모서리 좌표를 한 줄로 출력한다.
             실제 표시 경로(STA WPF)는 스모크에서 확인한다.
.CONTRACT    notify\popup.ps1
.INPUTS      없음.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 통과.
.SIDE-EFFECTS 임시 파일 없음.
.TESTS       docs\dsh-harness-notify-spec.md §4
.NOTES       작업 표시줄/화면 해상도에 따라 좌표는 달라지므로 값이 아니라 형식·포함 여부를 본다.
#>

#region INDEX
#   Assert-True   조건 비교
#   (main)        P1 dry-run 성공, P2 제목·본문 포함, P3 좌표 형식, P4 BOM
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'notify\popup.ps1'

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)
    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

Assert-True -Condition (Test-Path -LiteralPath $script) -Label 'P1 popup.ps1 존재'

$output = & pwsh -NoProfile -File $script -Title '테스트 제목' -Body '본문 내용' -DryRun 2>&1
$text = ($output -join ' ')
Assert-True -Condition ($LASTEXITCODE -eq 0 -and $text -match 'popup:') -Label 'P2 dry-run 성공'
Assert-True -Condition ($text -match '테스트 제목' -and $text -match '본문 내용') -Label 'P3 제목·본문 전달'
Assert-True -Condition ($text -match 'x=\d+ y=\d+ w=340 h=96') -Label 'P4 기하 형식'
Assert-True -Condition ($text -match 'sound=True') -Label 'P3b 기본 사운드 켜짐'
$silent = & pwsh -NoProfile -File $script -Title 't' -Body 'b' -Silent -DryRun 2>&1
Assert-True -Condition (($silent -join ' ') -match 'sound=False') -Label 'P3c -Silent 사운드 끔'

$bytes = [System.IO.File]::ReadAllBytes($script)
Assert-True -Condition ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) -Label 'P5 UTF-8 BOM'

Write-Host ''
Write-Host "popup: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
