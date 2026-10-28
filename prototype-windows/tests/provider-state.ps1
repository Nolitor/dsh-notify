<#
.SYNOPSIS    provider 계약(Get-State)이 design §2.2/§2.3 대로 상태 객체를 돌려주는지 검증한다.
.DESCRIPTION 임시 캐시에 2026 공휴일 파일을 직접 써서 네트워크 없이 검사한다.
             피크/오프피크 매핑, 대체근무일 플래그, 데이터 없음 강등(추정 배지),
             다음 전환 시각과 Detail 포맷을 확인한다.
.CONTRACT    providers\deepseek-peak.ps1 — Get-State
.INPUTS      없음. providers\deepseek-peak.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 임시 디렉터리 생성·삭제 (OS temp).
.TESTS       docs\2026-10-20-dsh-notify-design.md §2.2, §2.3, §3.1 / docs\deepseek-peak-spec.md §4
.NOTES       60초 폴링·UI 는 범위 밖. 여기서는 상태 객체만 본다.
#>

#region INDEX
#   New-TempCacheDir   캐시 루트 생성 + 2026 픽스처 배치 옵션
#   New-LocalNow       KST 오프셋 문자열 → 로컬 DateTime (TZ 무관)
#   Assert-Prop        객체 속성 기대값 비교
#   (main)             케이스 S1~S6
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$providerPath = Join-Path $repoRoot 'providers\deepseek-peak.ps1'
if (-not (Test-Path -LiteralPath $providerPath)) {
    Write-Host 'RED: providers\deepseek-peak.ps1 이 없습니다.'
    exit 1
}
. $providerPath

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([bool] $Condition, [string] $Label)

    if ($Condition) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label"
}

function New-TempCacheDir {
    param([switch] $With2026)

    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-notify-state-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    if ($With2026) {
        $json = @'
{
  "year": 2026,
  "papers": ["https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm"],
  "days": [
    { "name": "元旦", "date": "2026-01-01", "isOffDay": true },
    { "name": "春节", "date": "2026-02-17", "isOffDay": true },
    { "name": "中秋节", "date": "2026-09-26", "isOffDay": true },
    { "name": "国庆节", "date": "2026-09-20", "isOffDay": false },
    { "name": "国庆节", "date": "2026-10-01", "isOffDay": true },
    { "name": "国庆节", "date": "2026-10-05", "isOffDay": true },
    { "name": "国庆节", "date": "2026-10-10", "isOffDay": false }
  ]
}
'@
        $cacheDir = Join-Path $dir 'deepseek-peak'
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cacheDir '2026.json') -Value $json -Encoding UTF8
    }

    return $dir
}

function New-LocalNow {
    param([string] $KstIso)
    return [datetimeoffset]::Parse($KstIso, [cultureinfo]::InvariantCulture).LocalDateTime
}

function Assert-Prop {
    param(
        [object] $State,
        [string] $Name,
        [object] $Expected,
        [string] $Label
    )

    if ($null -eq $State) {
        $script:Fail++
        Write-Host "FAIL $Label — 상태 객체가 `$null"
        return
    }

    $actual = $State.$Name
    if ("$actual" -eq "$Expected") { $script:Pass++; Write-Host "PASS $Label"; return }

    $script:Fail++
    Write-Host "FAIL $Label — $Name='$actual' (기대 '$Expected')"
}

$withData = New-TempCacheDir -With2026
$noData = New-TempCacheDir

try {
    # S1 피크 매핑
    $state = Get-State -Now (New-LocalNow '2026-10-20T11:00:00+09:00') -Config @{ treatMakeupAsPeak = $true; refreshHours = 24 } -CacheDir $withData
    Assert-Prop -State $state -Name 'Id' -Expected 'deepseek-peak' -Label 'S1 Id'
    Assert-Prop -State $state -Name 'Severity' -Expected 'alert' -Label 'S1 피크 → alert'
    Assert-Prop -State $state -Name 'Headline' -Expected 'PEAK · 100%' -Label 'S1 Headline'
    Assert-True -Condition ($state.Detail -eq '→ 다음 구간까지 2h 00m') -Label "S1 Detail='$($state.Detail)' (기대 2h 00m)"
    Assert-True -Condition ($state.NotifyText -like '*피크*') -Label 'S1 NotifyText 피크 안내'

    # S2 오프피크 매핑
    $state = Get-State -Now (New-LocalNow '2026-10-20T14:00:00+09:00') -Config @{ treatMakeupAsPeak = $true; refreshHours = 24 } -CacheDir $withData
    Assert-Prop -State $state -Name 'Severity' -Expected 'ok' -Label 'S2 오프피크 → ok'
    Assert-Prop -State $state -Name 'Headline' -Expected 'OFF-PEAK · 50%' -Label 'S2 Headline'
    Assert-True -Condition ($state.Detail -notlike '*(추정)*') -Label 'S2 데이터 있으면 추정 배지 없음'

    # S3 대체근무일 + 플래그 off
    $state = Get-State -Now (New-LocalNow '2026-10-10T11:00:00+09:00') -Config @{ treatMakeupAsPeak = $false; refreshHours = 24 } -CacheDir $withData
    Assert-Prop -State $state -Name 'Severity' -Expected 'ok' -Label 'S3 대체근무일 off → ok'
    Assert-Prop -State $state -Name 'Headline' -Expected 'OFF-PEAK · 50%' -Label 'S3 Headline'

    # S4 데이터 없음 → 추정 배지, 예외 없음
    $state = Get-State -Now (New-LocalNow '2026-10-20T14:00:00+09:00') -Config @{ treatMakeupAsPeak = $true; refreshHours = 24 } -CacheDir $noData -NoFetch
    Assert-Prop -State $state -Name 'Severity' -Expected 'ok' -Label 'S4 데이터 없음 오프피크 → ok'
    Assert-True -Condition ($state.Detail -like '*(추정)*') -Label "S4 추정 배지 — Detail='$($state.Detail)'"

    # S5 데이터 없음 + 피크 추정 → alert 유지, NextChangeAt 존재
    $state = Get-State -Now (New-LocalNow '2027-01-05T11:00:00+09:00') -Config @{ treatMakeupAsPeak = $true; refreshHours = 24 } -CacheDir $noData -NoFetch
    Assert-Prop -State $state -Name 'Severity' -Expected 'alert' -Label 'S5 미공고 연도 평일 피크 → alert'
    Assert-True -Condition ($null -ne $state.NextChangeAt) -Label 'S5 NextChangeAt 존재'

    # S6 다음 전환 시각 = KST 13:00 (UTC 04:00)
    $state = Get-State -Now (New-LocalNow '2026-10-20T11:00:00+09:00') -Config @{ treatMakeupAsPeak = $true; refreshHours = 24 } -CacheDir $withData
    $expected = [datetimeoffset]::Parse('2026-10-20T13:00:00+09:00', [cultureinfo]::InvariantCulture).UtcDateTime
    Assert-True -Condition ($null -ne $state.NextChangeAt -and $state.NextChangeAt -eq $expected) -Label "S6 NextChangeAt=$($state.NextChangeAt) (기대 $expected UTC)"

    # S7 같은 순간이면 기기 시간대와 무관하게 같은 판정 — 판정 기준은 UTC 고정
    $kstNow = New-LocalNow '2026-10-20T11:00:00+09:00'   # 02:00Z
    $cestNow = New-LocalNow '2026-10-20T04:00:00+02:00'  # 02:00Z (같은 순간)
    $a = Get-State -Now $kstNow  -Config @{ treatMakeupAsPeak = $true; refreshHours = 24 } -CacheDir $withData
    $b = Get-State -Now $cestNow -Config @{ treatMakeupAsPeak = $true; refreshHours = 24 } -CacheDir $withData
    Assert-True -Condition ($a.Severity -eq $b.Severity -and $a.Headline -eq $b.Headline -and $a.NextChangeAt -eq $b.NextChangeAt) -Label 'S7 같은 순간 → 시간대와 무관하게 동일 판정'
}
finally {
    Remove-Item -LiteralPath $withData -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $noData -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "provider-state: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
