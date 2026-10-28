<#
.SYNOPSIS    DSH Notify 상주 프로세스를 콘솔 없이 시작한다 (VBScript 불필요).
.DESCRIPTION start.vbs 는 이 PC 에서 VBScript 엔진이 꺼져 있어 동작하지 않을 수 있다.
             이 스크립트는 pwsh 를 -Sta/숨김으로 다시 띄우고 즉시 반환한다.
             이미 실행 중이면 core.ps1 의 단일 인스턴스 뮤텍스가 중복 실행을 막는다.
.CONTRACT    core.ps1
.INPUTS      없음. $PSScriptRoot 기준.
.OUTPUTS     없음 (백그라운드 프로세스 시작).
.SIDE-EFFECTS pwsh 프로세스 생성.
.TESTS       수동: 실행 후 프로세스 확인
.NOTES       바로가기(.lnk)로 연결하면 콘솔 깜빡임 없이 쓸 수 있다.
#>

#region INDEX
#   (main)  core.ps1 경로 확인 → pwsh -Sta 숨김 실행
#endregion

$ErrorActionPreference = 'Stop'

$core = Join-Path $PSScriptRoot 'core.ps1'
if (-not (Test-Path -LiteralPath $core)) {
    Write-Host "FAIL: core.ps1 없음 — $core"
    exit 1
}

$arguments = "-Sta -NoProfile -WindowStyle Hidden -File `"$core`""
Start-Process -FilePath 'pwsh' -ArgumentList $arguments -WindowStyle Hidden
Write-Host 'DSH Notify 시작됨 (백그라운드)'
exit 0
