<#
.SYNOPSIS    tests\ 아래 모든 테스트 스크립트를 실행하고 결과를 집계한다.
.DESCRIPTION 이 파일을 제외한 tests\*.ps1 을 이름순으로 각각 별도 pwsh 프로세스에서 실행하고
             종료코드를 모아 요약을 출력한다. 하나라도 실패하면 1 을 반환한다.
.CONTRACT    docs\WORK-PROTOCOL.md §3 (자동 검사), docs\deepseek-peak-spec.md §5 (테스트)
.INPUTS      없음. $PSScriptRoot 기준.
.OUTPUTS     파일별 PASS/FAIL 요약. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 각 테스트가 자기 임시 캐시를 만들 수 있다.
.TESTS       이 파일 자체가 러너다.
.NOTES       테스트 스크립트는 단독 실행 가능해야 한다.
#>

#region INDEX
#   (main)   tests\*.ps1 수집 → 자식 프로세스 실행 → 집계
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -File | Where-Object { $_.Name -ne 'run-all.ps1' } | Sort-Object Name)

if ($files.Count -eq 0) {
    Write-Host 'TOTAL: 0 files'
    exit 0
}

$failed = @()
foreach ($file in $files) {
    Write-Host "=== $($file.Name) ==="
    $output = & pwsh -NoProfile -NoLogo -File $file.FullName 2>&1
    $code = $LASTEXITCODE
    foreach ($line in @($output)) { Write-Host $line }
    if ($code -ne 0) { $failed += $file.Name }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "TOTAL: $($files.Count) files, $($files.Count - $failed.Count) passed, $($failed.Count) failed — $($failed -join ', ')"
    exit 1
}

Write-Host "TOTAL: $($files.Count) files, $($files.Count) passed, 0 failed"
exit 0
