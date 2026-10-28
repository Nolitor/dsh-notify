<#
.SYNOPSIS    접속 지역(공인 IP) 조회와 기기 시간대 대조 로직을 검증한다.
.DESCRIPTION 하루 1회 캐시되는 IP 지역 정보의 재사용·폴백을 확인하고, 기기 시간대와
             실제 접속 지역의 UTC 오프셋이 다를 때 Mismatch 가 서는지 검사한다.
             네트워크 없이 캐시 파일을 직접 만들어 결정적으로 검사한다.
.CONTRACT    providers\deepseek-peak.ps1 — Resolve-PeakTimeZone, Get-PublicRegion, Get-PeakReferenceTimeZones
.INPUTS      없음. providers\deepseek-peak.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 임시 디렉터리 생성·삭제.
.TESTS       docs\deepseek-peak-spec.md §4.4 (기기 시간대 vs 접속 지역)
.NOTES       VPN 은 IP 지역을 바꾸므로 결과는 '힌트'로만 쓴다. 판정 자체는 UTC 고정.
#>

#region INDEX
#   New-TempCacheDir   임시 캐시 루트
#   Write-RegionCache  region.json 작성 + mtime 조정
#   Assert-Value       스칼라 비교
#   (main)             R1-R8 : 캐시 재사용·폴백·불일치 판정
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

function Assert-Value {
    param([object] $Actual, [object] $Expected, [string] $Label)

    if ("$Actual" -eq "$Expected") { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$Actual' (기대 '$Expected')"
}

function New-TempCacheDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-region-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Write-RegionCache {
    param([string] $CacheDir, [string] $Json, [timespan] $Age = [timespan]::Zero)

    $file = Join-Path $CacheDir 'region.json'
    Set-Content -LiteralPath $file -Value $Json -Encoding UTF8
    if ($Age -gt [timespan]::Zero) { (Get-Item -LiteralPath $file).LastWriteTime = (Get-Date) - $Age }
    return $file
}

$usRegion = '{"ip":"1.2.3.4","country":"US","region":"California","city":"Los Angeles","timezone":"America/Los_Angeles"}'
$krRegion = '{"ip":"211.207.9.156","country":"KR","region":"Incheon","city":"Incheon","timezone":"Asia/Seoul"}'
$korea = [System.TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time')
$tokyo = [System.TimeZoneInfo]::FindSystemTimeZoneById('Asia/Tokyo')

$dir = New-TempCacheDir
try {
    # R1 신선한 캐시 재사용 (네트워크 차단)
    [void](Write-RegionCache -CacheDir $dir -Json $usRegion -Age ([timespan]::FromHours(1)))
    $ref = Get-PeakReferenceTimeZones -CacheDir $dir -DeviceTimeZone $korea -NoFetch
    Assert-Value -Actual $ref.Source -Expected 'cache' -Label 'R1 신선한 캐시 → Source=cache'
    Assert-Value -Actual $ref.Region.Id -Expected 'America/Los_Angeles' -Label 'R1 지역 시간대 해석'
    Assert-Value -Actual $ref.Country -Expected 'US' -Label 'R1 국가 코드'

    # R2 만료 캐시 폴백 (48h, 네트워크 차단)
    [void](Write-RegionCache -CacheDir $dir -Json $usRegion -Age ([timespan]::FromHours(48)))
    $ref = Get-PeakReferenceTimeZones -CacheDir $dir -DeviceTimeZone $korea -NoFetch
    Assert-Value -Actual $ref.Source -Expected 'cache' -Label 'R2 만료 캐시 폴백'
    Assert-Value -Actual $ref.Region.Id -Expected 'America/Los_Angeles' -Label 'R2 만료 캐시 지역 유지'

    # R3 캐시 없음 → 기기 시간대
    $empty = New-TempCacheDir
    try {
        $ref = Get-PeakReferenceTimeZones -CacheDir $empty -DeviceTimeZone $korea -NoFetch
        Assert-Value -Actual $ref.Source -Expected 'device' -Label 'R3 캐시 없음 → Source=device'
        Assert-Value -Actual $ref.Region.Id -Expected $korea.Id -Label 'R3 기기 시간대로 폴백'
        Assert-Value -Actual $ref.Mismatch -Expected $false -Label 'R3 불일치 없음'

        # R4 손상 JSON → 기기 폴백
        [void](Write-RegionCache -CacheDir $empty -Json '{ "timezone": "America/Los_Angeles", "country": ' -Age ([timespan]::FromMinutes(5)))
        $ref = Get-PeakReferenceTimeZones -CacheDir $empty -DeviceTimeZone $korea -NoFetch
        Assert-Value -Actual $ref.Source -Expected 'device' -Label 'R4 손상 JSON → device'

        # R5 알 수 없는 시간대 ID → 기기 폴백
        [void](Write-RegionCache -CacheDir $empty -Json '{"ip":"1.2.3.4","country":"US","timezone":"Mars/Olympus"}' -Age ([timespan]::FromMinutes(5)))
        $ref = Get-PeakReferenceTimeZones -CacheDir $empty -DeviceTimeZone $korea -NoFetch
        Assert-Value -Actual $ref.Source -Expected 'device' -Label 'R5 미지 시간대 → device'
    }
    finally {
        Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
    }

    # R6 기기 KST vs 지역 미국 → 불일치
    [void](Write-RegionCache -CacheDir $dir -Json $usRegion -Age ([timespan]::FromHours(1)))
    $ref = Get-PeakReferenceTimeZones -CacheDir $dir -DeviceTimeZone $korea -NoFetch
    Assert-Value -Actual $ref.Mismatch -Expected $true -Label 'R6 KST 기기 + US 지역 → 불일치'

    # R7 기기 KST vs 지역 KR → 일치
    [void](Write-RegionCache -CacheDir $dir -Json $krRegion -Age ([timespan]::FromHours(1)))
    $ref = Get-PeakReferenceTimeZones -CacheDir $dir -DeviceTimeZone $korea -NoFetch
    Assert-Value -Actual $ref.Mismatch -Expected $false -Label 'R7 KST 기기 + KR 지역 → 일치'

    # R8 오프셋이 같으면 ID 가 달라도 불일치 아님 (서울 vs 도쿄)
    $ref = Get-PeakReferenceTimeZones -CacheDir $dir -DeviceTimeZone $tokyo -NoFetch
    Assert-Value -Actual $ref.Mismatch -Expected $false -Label 'R8 같은 오프셋 → 불일치 아님'
}
finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "region: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
