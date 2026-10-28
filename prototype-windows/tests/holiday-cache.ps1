<#
.SYNOPSIS    공휴일 캐시 로더(Get-HolidayData)의 캐시 우선·강등 정책을 검증한다.
.DESCRIPTION 임시 디렉터리에 캐시 파일을 직접 만들어 네트워크 없이 검사한다.
             신선한 캐시 재사용, 만료 캐시 폴백, 파일 없음, 손상 JSON, 연도 불일치,
             미공고(papers 비어 있음) 수용 여부를 확인한다.
.CONTRACT    providers\deepseek-peak.ps1 — Get-HolidayData
.INPUTS      없음. providers\deepseek-peak.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 임시 디렉터리 생성·삭제 (OS temp).
.TESTS       docs\deepseek-peak-spec.md §2.5 (캐시 정책)
.NOTES       다운로드 경로는 네트워크 의존이라 테스트하지 않는다 (-NoFetch 로 결정적 검사).
#>

#region INDEX
#   New-TempCacheDir   OS temp 아래 고유 캐시 루트 생성
#   Write-CacheFile    deepseek-peak\{year}.json 작성 + mtime 조정
#   Assert-True        불리언 조건 비교
#   (main)             케이스 C1~C7
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

    if ($Condition) {
        $script:Pass++
        Write-Host "PASS $Label"
        return
    }
    $script:Fail++
    Write-Host "FAIL $Label"
}

function New-TempCacheDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-notify-cache-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Write-CacheFile {
    param(
        [string]   $CacheDir,
        [int]      $Year,
        [string]   $Json,
        [timespan] $Age = [timespan]::Zero
    )

    $dir = Join-Path $CacheDir 'deepseek-peak'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir "$Year.json"
    Set-Content -LiteralPath $file -Value $Json -Encoding UTF8
    if ($Age -gt [timespan]::Zero) {
        (Get-Item -LiteralPath $file).LastWriteTime = (Get-Date) - $Age
    }
    return $file
}

$valid2026 = @'
{
  "year": 2026,
  "papers": ["https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm"],
  "days": [
    { "name": "国庆节", "date": "2026-10-01", "isOffDay": true },
    { "name": "国庆节", "date": "2026-10-02", "isOffDay": true },
    { "name": "国庆节", "date": "2026-10-10", "isOffDay": false }
  ]
}
'@

$empty2027 = '{"year": 2027, "papers": [], "days": []}'

$root = New-TempCacheDir
try {
    # C1 신선한 캐시 재사용
    [void](Write-CacheFile -CacheDir $root -Year 2026 -Json $valid2026 -Age ([timespan]::FromHours(1)))
    $data = Get-HolidayData -Year 2026 -CacheDir $root -RefreshHours 24 -NoFetch
    Assert-True -Condition ($null -ne $data -and $data.year -eq 2026 -and @($data.days).Count -eq 3) -Label 'C1 신선한 캐시(1h) 재사용'

    # C2 만료 캐시 폴백 (48h 경과, 네트워크 차단)
    [void](Write-CacheFile -CacheDir $root -Year 2026 -Json $valid2026 -Age ([timespan]::FromHours(48)))
    $data = Get-HolidayData -Year 2026 -CacheDir $root -RefreshHours 24 -NoFetch
    Assert-True -Condition ($null -ne $data -and @($data.days).Count -eq 3) -Label 'C2 만료 캐시(48h) 폴백'

    # C3 파일 없음
    $data = Get-HolidayData -Year 2028 -CacheDir $root -RefreshHours 24 -NoFetch
    Assert-True -Condition ($null -eq $data) -Label 'C3 캐시 없음 → $null'

    # C4 손상 JSON
    [void](Write-CacheFile -CacheDir $root -Year 2026 -Json '{ "year": 2026, "papers": [' -Age ([timespan]::FromMinutes(5)))
    $data = Get-HolidayData -Year 2026 -CacheDir $root -RefreshHours 24 -NoFetch
    Assert-True -Condition ($null -eq $data) -Label 'C4 손상 JSON → $null'

    # C5 미공고(papers 빈 배열) 수용 — 판정 불가는 별도 계층에서 처리
    [void](Write-CacheFile -CacheDir $root -Year 2027 -Json $empty2027 -Age ([timespan]::FromMinutes(5)))
    $data = Get-HolidayData -Year 2027 -CacheDir $root -RefreshHours 24 -NoFetch
    Assert-True -Condition ($null -ne $data -and $data.year -eq 2027 -and @($data.papers).Count -eq 0) -Label 'C5 미공고 데이터(papers: []) 수용'

    # C6 요청 연도와 파일 내용 연도 불일치
    [void](Write-CacheFile -CacheDir $root -Year 2026 -Json $empty2027 -Age ([timespan]::FromMinutes(5)))
    $data = Get-HolidayData -Year 2026 -CacheDir $root -RefreshHours 24 -NoFetch
    Assert-True -Condition ($null -eq $data) -Label 'C6 연도 불일치 → $null'

    # C7 papers 타입 오류 (배열 아님)
    $badPapers = '{"year": 2026, "papers": "https://example.invalid/p.htm", "days": []}'
    [void](Write-CacheFile -CacheDir $root -Year 2026 -Json $badPapers -Age ([timespan]::FromMinutes(5)))
    $data = Get-HolidayData -Year 2026 -CacheDir $root -RefreshHours 24 -NoFetch
    Assert-True -Condition ($null -eq $data) -Label 'C7 papers 타입 오류 → $null'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "holiday-cache: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
