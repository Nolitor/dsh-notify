<#
.SYNOPSIS    DeepSeek 과금 구간(피크 100% / 오프피크 50%) 판정 provider.
.DESCRIPTION UTC 시각과 공휴일 데이터로 피크/오프피크를 판정하고, 상태가 뒤집히는 다음 시각을 계산해
             UI 계약(design §2.2)에 맞는 상태 객체 1건을 돌려준다. 공휴일은 cache\deepseek-peak\{year}.json 에 캐시한다.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §2.2 (provider 계약), §2.3 (severity 매핑)
.INPUTS      Get-State: Now(로컬 시각), Config(providers.deepseek-peak 섹션), CacheDir(캐시 절대 경로)
.OUTPUTS     Id, Label, Severity(alert|ok), Headline, Detail, NextChangeAt, NotifyText
.SIDE-EFFECTS 캐시 파일 읽기/쓰기. 갱신은 스레드 작업 1개로 비동기 실행(폴링 비차단), 첫 실행만 최대 10초 동기 대기.
             접속 지역(IP) 조회는 하루 1회·최대 5초, 실패 시 1시간 쿨다운 후 기기 시간대로 폴백.
.TESTS       tests\peak-decisions.ps1, tests\holiday-cache.ps1, tests\provider-config.ps1, tests\holiday-refresh.ps1, tests\local-window.ps1, tests\region.ps1, tests\provider-state.ps1
.NOTES       docs\deepseek-peak-spec.md §3 (판정), §4 (상태 출력), §2.5 (캐시 정책·비동기 갱신)
#>

#region INDEX
#   ConvertTo-Utc         입력 시각 → UTC (Unspecified 는 UTC 로 간주)
#   Test-HolidayPayload   공휴일 JSON 구조 검증 (year 일치·days 배열·papers 허용)
#   Get-PeakConfig        설정 기본값 정규화 (대체근무일=피크, 갱신 240h=10일)     tests\provider-config.ps1 C0-C1
#   Get-HolidayCacheTtl   캐시 TTL — 미공고(papers 빈 배열)는 24h 로 단축      tests\provider-config.ps1 T1-T5
#   Get-HolidayRefreshPlan 갱신 판단 sync|async|skip (실행 중·쿨다운 고려)    tests\holiday-refresh.ps1 R1-R9
#   Save-HolidayPayload   다운로드·검증·원자적 쓰기 (동기 경로와 작업 공용)
#   Start-HolidayRefresh  백그라운드 스레드 작업 1개로 캐시 갱신
#   Get-HolidayData       캐시 우선 로더 — 만료 시 비동기 갱신 후 기존 캐시 반환   tests\holiday-cache.ps1 C1-C7
#   Get-PeakDecision      피크 판정 (IsPeak/Reason/Confidence)                        tests\peak-decisions.ps1 #1-9
#   Get-PeakNextChange    상태가 뒤집히는 첫 분 (최대 8일)                            tests\peak-decisions.ps1 전환 3
#   Get-PeakLocalWindow   UTC 구간 → 지정 시간대(기본 로컬) 창 목록                  tests\local-window.ps1 W1-W5
#   Resolve-PeakTimeZone  시간대 ID(IANA/Windows) → TimeZoneInfo
#   Test-PublicRegionPayload IP 지역 응답 검증 (timezone 해석 가능 여부)
#   Get-PublicRegion      접속 지역(IP) 정보 하루 1회 캐시 — ipinfo.io, 실패 시 기기 폴백
#   Get-PeakReferenceTimeZones 기기 시간대 vs 접속 지역 시간대 대조·불일치 판정   tests\region.ps1 R1-R8
#   Format-PeakSpan       남은 시간 → '2h 00m' / '42m' / '곧 구간 전환'               tests\provider-state.ps1 S1
#   Get-State             provider 계약 진입점 (UI 는 이 객체만 본다)                  tests\provider-state.ps1 S1-S6
#endregion

$script:Weekend = @([System.DayOfWeek]::Saturday, [System.DayOfWeek]::Sunday)
$script:HolidaySource = 'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{0}.json'
$script:ProviderPath = $PSCommandPath
$script:RefreshRetryHours = 1
$script:Refresh = @{ Job = $null; LastAttempt = [datetime]::MinValue }
$script:RegionSource = 'https://ipinfo.io/json'
$script:RegionRetryHours = 1
$script:RegionLastAttempt = [datetime]::MinValue

function ConvertTo-Utc {
    param([datetime] $Value)

    if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value }
    if ($Value.Kind -eq [System.DateTimeKind]::Local) { return $Value.ToUniversalTime() }
    return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
}

function Test-HolidayPayload {
    param([object] $Data, [int] $Year)

    if ($null -eq $Data) { return $false }
    if ($null -eq $Data.year -or $Data.year -ne $Year) { return $false }
    if ($null -eq $Data.days) { return $false }
    if ($null -ne $Data.papers -and $Data.papers -isnot [System.Array]) { return $false }
    return $true
}

function Get-PeakConfig {
    param([hashtable] $Config)

    $cfg = if ($null -eq $Config) { @{} } else { $Config }
    return [pscustomobject]@{
        TreatMakeupAsPeak = if ($cfg.ContainsKey('treatMakeupAsPeak')) { [bool]$cfg['treatMakeupAsPeak'] } else { $true }
        RefreshHours      = if ($cfg.ContainsKey('refreshHours')) { [int]$cfg['refreshHours'] } else { 240 }
    }
}

function Get-HolidayCacheTtl {
    param([int] $RefreshHours, [object] $Data)

    # 미공고(papers 빈 배열)는 TTL 단위로 묵이면 연초 내내 추정으로 남는다. 24시간으로 조인다.
    if ($null -ne $Data -and $null -ne $Data.papers -and @($Data.papers).Count -eq 0) {
        return [Math]::Min($RefreshHours, 24)
    }
    return $RefreshHours
}

function Get-HolidayRefreshPlan {
    param(
        [int]    $TtlHours,
        [double] $AgeHours,
        [switch] $HasCache,
        [switch] $JobRunning,
        [double] $LastAttemptHoursAgo = [double]::MaxValue,
        [double] $RetryHours = 1
    )

    # 캐시가 없으면 첫 실행이므로 동기로 받아온다. (10초 상한)
    if (-not $HasCache) { return 'sync' }
    if ($JobRunning) { return 'skip' }
    if ($TtlHours -le 0 -or $AgeHours -ge $TtlHours) {
        if ($LastAttemptHoursAgo -lt $RetryHours) { return 'skip' }
        return 'async'
    }
    return 'skip'
}

function Save-HolidayPayload {
    param([string] $Uri, [int] $Year, [string] $File)

    $downloaded = Invoke-RestMethod -Uri $Uri -TimeoutSec 10 -ErrorAction Stop
    if (-not (Test-HolidayPayload -Data $downloaded -Year $Year)) { return $null }

    $dir = Split-Path -Parent $File
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # 폴링 중인 프로세스가 반쯤 쓰인 JSON 을 읽지 않도록 임시 파일 후 교체한다.
    $temp = "$File.tmp"
    $downloaded | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $File -Force
    return $downloaded
}

function Start-HolidayRefresh {
    param([int] $Year, [string] $File)

    $providerPath = $script:ProviderPath
    if ([string]::IsNullOrWhiteSpace($providerPath)) { $providerPath = $PSCommandPath }
    $uri = $script:HolidaySource -f $Year

    $script:Refresh.Job = Start-ThreadJob -ScriptBlock {
        param($ProviderPath, $Uri, $Year, $File)
        try {
            . $ProviderPath
            [void](Save-HolidayPayload -Uri $Uri -Year $Year -File $File)
        }
        catch {
            # 실패는 다음 쿨다운(1시간) 후 재시도한다.
        }
    } -ArgumentList $providerPath, $uri, $Year, $File

    $script:Refresh.LastAttempt = [datetime]::UtcNow
}

function Get-HolidayData {
    param(
        [int]    $Year,
        [string] $CacheDir,
        [int]    $RefreshHours = 240,
        [switch] $NoFetch
    )

    $dir = Join-Path $CacheDir 'deepseek-peak'
    $file = Join-Path $dir "$Year.json"
    $cached = $null
    $ageHours = 0

    if (Test-Path -LiteralPath $file) {
        try {
            $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            if (Test-HolidayPayload -Data $parsed -Year $Year) {
                $cached = $parsed
                # TTL 은 절대 시각으로 계산한다. 로컬 벽시계 차이는 DST 전환에서 1시간 어긋난다.
                $ageHours = ([datetime]::UtcNow - (Get-Item -LiteralPath $file).LastWriteTimeUtc).TotalHours
            }
        }
        catch {
            $cached = $null
        }
    }

    if ($NoFetch) { return $cached }

    if ($null -ne $script:Refresh.Job -and $script:Refresh.Job.State -ne 'Running') {
        $script:Refresh.Job = $null
    }
    $jobRunning = $null -ne $script:Refresh.Job

    $ttl = Get-HolidayCacheTtl -RefreshHours $RefreshHours -Data $cached
    $lastAttemptHoursAgo = if ($script:Refresh.LastAttempt -eq [datetime]::MinValue) {
        [double]::MaxValue
    }
    else {
        ([datetime]::UtcNow - $script:Refresh.LastAttempt.ToUniversalTime()).TotalHours
    }
    $plan = Get-HolidayRefreshPlan `
        -TtlHours $ttl `
        -AgeHours $ageHours `
        -HasCache:($null -ne $cached) `
        -JobRunning:$jobRunning `
        -LastAttemptHoursAgo $lastAttemptHoursAgo `
        -RetryHours $script:RefreshRetryHours

    if ($plan -eq 'skip') { return $cached }

    if ($plan -eq 'async') {
        Start-HolidayRefresh -Year $Year -File $file
        return $cached
    }

    try {
        $saved = Save-HolidayPayload -Uri ($script:HolidaySource -f $Year) -Year $Year -File $file
        if ($null -ne $saved) { return $saved }
    }
    catch {
        # 네트워크·파싱 실패는 조용히 강등한다. 첫 실행이면 데이터 없이 진행한다.
    }

    return $cached
}

function Get-PeakDecision {
    param(
        [datetime] $UtcNow,
        [object]   $HolidayData,
        [bool]     $TreatMakeupAsPeak = $true
    )

    $utc = ConvertTo-Utc -Value $UtcNow
    # 중국 공휴일은 베이징 달력일(UTC+8) 기준이다. 저장된 date 값과 직접 대조해야
    # 대체근무일(调休)의 시작/끝이 UTC 자정이 아니라 베이징 자정에 맞는다.
    $beijing = $utc.AddHours(8)
    $year = $beijing.Year

    $hasData = $false
    if ($null -ne $HolidayData) {
        $paperCount = 0
        if ($null -ne $HolidayData.papers) { $paperCount = @($HolidayData.papers).Count }
        if ($HolidayData.year -eq $year -and $paperCount -gt 0) { $hasData = $true }
    }
    $confidence = if ($hasData) { 'exact' } else { 'estimated' }

    if ($hasData) {
        $dateKey = $beijing.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        foreach ($day in @($HolidayData.days)) {
            if ($null -eq $day) { continue }
            if ($day.date -ne $dateKey) { continue }

            if ($day.isOffDay -eq $true) {
                return [pscustomobject]@{ IsPeak = $false; Reason = 'holiday'; Confidence = 'exact' }
            }
            return [pscustomobject]@{
                IsPeak     = [bool]$TreatMakeupAsPeak
                Reason     = 'makeup-workday'
                Confidence = 'exact'
            }
        }
    }

    if ($script:Weekend -contains $utc.DayOfWeek) {
        return [pscustomobject]@{ IsPeak = $false; Reason = 'weekend'; Confidence = $confidence }
    }

    $hour = $utc.Hour
    $inPeakWindow = ($hour -ge 1 -and $hour -lt 4) -or ($hour -ge 6 -and $hour -lt 10)
    if ($inPeakWindow) {
        return [pscustomobject]@{ IsPeak = $true; Reason = 'weekday-peak'; Confidence = $confidence }
    }
    return [pscustomobject]@{ IsPeak = $false; Reason = 'weekday-offpeak'; Confidence = $confidence }
}

function Get-PeakNextChange {
    param(
        [datetime] $UtcNow,
        [object]   $HolidayData,
        [bool]     $TreatMakeupAsPeak = $true,
        [int]      $MaxDays = 8
    )

    $utc = ConvertTo-Utc -Value $UtcNow
    $current = (Get-PeakDecision -UtcNow $utc -HolidayData $HolidayData -TreatMakeupAsPeak $TreatMakeupAsPeak).IsPeak
    $cursor = $utc.AddSeconds(-$utc.Second).AddMilliseconds(-$utc.Millisecond).AddMinutes(1)
    $limit = $MaxDays * 1440

    for ($i = 0; $i -lt $limit; $i++) {
        $next = (Get-PeakDecision -UtcNow $cursor -HolidayData $HolidayData -TreatMakeupAsPeak $TreatMakeupAsPeak).IsPeak
        if ($next -ne $current) { return $cursor }
        $cursor = $cursor.AddMinutes(1)
    }

    return $null
}

function Get-PeakLocalWindow {
    param(
        [datetime] $UtcNow,
        [object]   $HolidayData,
        [bool]     $TreatMakeupAsPeak = $true,
        [System.TimeZoneInfo] $TimeZone,
        [int]      $Count = 2
    )

    if ($null -eq $TimeZone) { $TimeZone = [System.TimeZoneInfo]::Local }
    if ($Count -lt 1) { return @() }

    $cursor = ConvertTo-Utc -Value $UtcNow
    $current = (Get-PeakDecision -UtcNow $cursor -HolidayData $HolidayData -TreatMakeupAsPeak $TreatMakeupAsPeak).IsPeak
    $windows = @()

    while ($windows.Count -lt $Count) {
        $next = Get-PeakNextChange -UtcNow $cursor -HolidayData $HolidayData -TreatMakeupAsPeak $TreatMakeupAsPeak
        if ($null -eq $next) { break }

        $windows += [pscustomobject]@{
            StartUtc   = $cursor
            EndUtc     = $next
            StartLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc($cursor, $TimeZone)
            EndLocal   = [System.TimeZoneInfo]::ConvertTimeFromUtc($next, $TimeZone)
            IsPeak     = $current
        }

        $cursor = $next
        $current = (Get-PeakDecision -UtcNow $next -HolidayData $HolidayData -TreatMakeupAsPeak $TreatMakeupAsPeak).IsPeak
    }

    return $windows
}

function Resolve-PeakTimeZone {
    param([string] $Id)

    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
    try { return [System.TimeZoneInfo]::FindSystemTimeZoneById($Id) }
    catch { return $null }
}

function Test-PublicRegionPayload {
    param([object] $Data)

    if ($null -eq $Data) { return $false }
    if ([string]::IsNullOrWhiteSpace($Data.timezone)) { return $false }
    return $null -ne (Resolve-PeakTimeZone -Id $Data.timezone)
}

function Get-PublicRegion {
    param(
        [string] $CacheDir,
        [int]    $RefreshHours = 24,
        [switch] $NoFetch
    )

    $file = Join-Path $CacheDir 'region.json'
    $cached = $null
    $fresh = $false

    if (Test-Path -LiteralPath $file) {
        try {
            $parsed = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if (Test-PublicRegionPayload -Data $parsed) {
                $cached = $parsed
                $age = (Get-Date) - (Get-Item -LiteralPath $file).LastWriteTime
                $fresh = $RefreshHours -gt 0 -and $age.TotalHours -lt $RefreshHours
            }
        }
        catch {
            $cached = $null
        }
    }

    if ($fresh) { return [pscustomobject]@{ Data = $cached; Source = 'cache' } }
    if ($NoFetch) { return $(if ($null -ne $cached) { [pscustomobject]@{ Data = $cached; Source = 'cache' } } else { $null }) }
    if (((Get-Date) - $script:RegionLastAttempt).TotalHours -lt $script:RegionRetryHours) {
        return $(if ($null -ne $cached) { [pscustomobject]@{ Data = $cached; Source = 'cache' } } else { $null })
    }

    $script:RegionLastAttempt = Get-Date
    try {
        $fetch = Invoke-RestMethod -Uri $script:RegionSource -TimeoutSec 5 -ErrorAction Stop
        if (Test-PublicRegionPayload -Data $fetch) {
            $payload = [pscustomobject]@{
                ip       = $fetch.ip
                country  = $fetch.country
                region   = $fetch.region
                city     = $fetch.city
                timezone = $fetch.timezone
            }
            if (-not (Test-Path -LiteralPath $CacheDir)) {
                New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
            }
            $payload | ConvertTo-Json | Set-Content -LiteralPath $file -Encoding UTF8
            return [pscustomobject]@{ Data = $payload; Source = 'network' }
        }
    }
    catch {
        # IP 조회 실패는 기기 시간대로 폴백한다.
    }

    return $(if ($null -ne $cached) { [pscustomobject]@{ Data = $cached; Source = 'cache' } } else { $null })
}

function Get-PeakReferenceTimeZones {
    param(
        [string] $CacheDir,
        [System.TimeZoneInfo] $DeviceTimeZone,
        [switch] $NoFetch
    )

    if ($null -eq $DeviceTimeZone) { $DeviceTimeZone = [System.TimeZoneInfo]::Local }

    $loaded = Get-PublicRegion -CacheDir $CacheDir -NoFetch:$NoFetch
    if ($null -eq $loaded) {
        return [pscustomobject]@{
            Device   = $DeviceTimeZone
            Region   = $DeviceTimeZone
            RegionId = $DeviceTimeZone.Id
            Country  = ''
            Label    = "기기 시간대 ($($DeviceTimeZone.Id))"
            Source   = 'device'
            Mismatch = $false
        }
    }

    $data = $loaded.Data
    $regionTz = Resolve-PeakTimeZone -Id $data.timezone
    if ($null -eq $regionTz) {
        return [pscustomobject]@{
            Device   = $DeviceTimeZone
            Region   = $DeviceTimeZone
            RegionId = $DeviceTimeZone.Id
            Country  = ''
            Label    = "기기 시간대 ($($DeviceTimeZone.Id))"
            Source   = 'device'
            Mismatch = $false
        }
    }

    $place = (@($data.city, $data.country) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
    if ([string]::IsNullOrWhiteSpace($place)) { $place = $data.timezone }

    $now = Get-Date
    $mismatch = $regionTz.GetUtcOffset($now) -ne $DeviceTimeZone.GetUtcOffset($now)

    return [pscustomobject]@{
        Device   = $DeviceTimeZone
        Region   = $regionTz
        RegionId = $regionTz.Id
        Country  = $data.country
        Label    = "$place ($($data.timezone))"
        Source   = $loaded.Source
        Mismatch = $mismatch
    }
}

function Format-PeakSpan {
    param([object] $NextChangeAt, [datetime] $UtcNow)

    if ($null -eq $NextChangeAt) { return '전환 시각 미상' }

    $delta = ([datetime]$NextChangeAt) - $UtcNow
    $minutes = [int][Math]::Floor($delta.TotalMinutes)
    if ($minutes -lt 1) { return '곧 구간 전환' }

    $hours = [int][Math]::Floor($minutes / 60)
    $rest = $minutes % 60
    if ($hours -gt 0) { return "${hours}h $('{0:00}' -f $rest)m" }
    return "${rest}m"
}

function Get-State {
    param(
        [datetime]  $Now,
        [hashtable] $Config,
        [string]    $CacheDir,
        [switch]    $NoFetch
    )

    if (-not $PSBoundParameters.ContainsKey('Now')) { $Now = Get-Date }
    if ($null -eq $Config) { $Config = @{} }
    if ([string]::IsNullOrWhiteSpace($CacheDir)) {
        $CacheDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'cache'
    }

    $peakConfig = Get-PeakConfig -Config $Config
    $treatMakeup = $peakConfig.TreatMakeupAsPeak
    $refreshHours = $peakConfig.RefreshHours

    $utc = $Now.ToUniversalTime()
    $holidayYear = $utc.AddHours(8).Year
    $holiday = Get-HolidayData -Year $holidayYear -CacheDir $CacheDir -RefreshHours $refreshHours -NoFetch:$NoFetch
    $decision = Get-PeakDecision -UtcNow $utc -HolidayData $holiday -TreatMakeupAsPeak $treatMakeup
    $nextChange = Get-PeakNextChange -UtcNow $utc -HolidayData $holiday -TreatMakeupAsPeak $treatMakeup

    $detail = '→ 다음 구간까지 ' + (Format-PeakSpan -NextChangeAt $nextChange -UtcNow $utc)
    if ($decision.Confidence -eq 'estimated') {
        $badge = '추정'
        if ($null -ne $holiday -and $null -ne $holiday.papers -and @($holiday.papers).Count -eq 0) {
            $badge = '추정·공고 전'
        }
        $detail += " ($badge)"
    }

    $isPeak = $decision.IsPeak
    return [pscustomobject]@{
        Id           = 'deepseek-peak'
        Label        = 'DeepSeek 과금'
        Severity     = if ($isPeak) { 'alert' } else { 'ok' }
        Headline     = if ($isPeak) { 'PEAK · 100%' } else { 'OFF-PEAK · 50%' }
        Detail       = $detail
        NextChangeAt = $nextChange
        NotifyText   = if ($isPeak) {
            '딥시크 피크 구간입니다 (100%). 대량 작업은 50% 구간까지 미루는 것을 검토하세요.'
        }
        else {
            '오프피크 구간입니다 (50%). 지금이 대량 작업 적기입니다.'
        }
    }
}
