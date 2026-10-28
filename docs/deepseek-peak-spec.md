# DeepSeek 과금 구간 인디케이터 — 기능 스펙

> 상태: active · 최종 갱신: 2026-10-20 · git: main @ milestone-1 · 상위: [2026-10-20-dsh-notify-design.md](./2026-10-20-dsh-notify-design.md)

- 상위 문서: [2026-10-20-dsh-notify-design.md](./2026-10-20-dsh-notify-design.md)
- provider id: `deepseek-peak`
- 구현 파일: `providers/deepseek-peak.ps1`

## 인덱스

| § | 섹션 | 이동 | 한 줄 요약 |
|---|---|---|---|
| 1 | 요금 규칙 | [§1](#1-요금-규칙) | 피크 창, KST 환산, 단가 |
| 2 | 공휴일 데이터 | [§2](#2-공휴일-데이터) | 소스, 형식, 캐시 정책 |
| 3 | 판정 함수 | [§3](#3-판정-함수) | 시그니처, 알고리즘, 대체근무일 가정 |
| 4 | 상태 출력 | [§4](#4-상태-출력) | 상태 객체와 다음 전환 시각 |
| 5 | 테스트 | [§5](#5-테스트) | 8케이스 표, 통합 테스트, 글로벌 시간대 매트릭스 |
| 6 | 설정 섹션 | [§6](#6-설정-섹션) | providers.deepseek-peak |
| 7 | 사용자가 알아야 할 한계 | [§7](#7-사용자가-알아야-할-한계) | 오해 방지 |

---

## 1. 요금 규칙

공식 문서 [Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing) 원문:

> Off-peak rates are half of the peak rates. Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday, excluding Chinese public holidays. All other hours are off-peak, including weekends and Chinese public holidays in full.

### 1.1 한국 시간 환산

한국은 서머타임이 없다. `KST = UTC + 9h`.

```
UTC 01:00–04:00  →  KST 10:00–13:00
UTC 06:00–10:00  →  KST 15:00–19:00
```

요일 경계를 넘지 않는다. UTC 평일 최대 시각 10:00 + 9h = KST 19:00, 같은 날.

> 아래 §1.2 표는 **KST 기준 설명**이다. 구간 정의 자체는 UTC 고정이므로, 다른 시간대에서는
> 요일 경계까지 밀린다 — 변환 규칙은 §4.3 참고.

### 1.2 한국 시간 기준 결과

| 구간 | 요금 |
|---|---|
| 평일 00:00–10:00 | 50% |
| 평일 10:00–13:00 | **100%** |
| 평일 13:00–15:00 | 50% |
| 평일 15:00–19:00 | **100%** |
| 평일 19:00–24:00 | 50% |
| 토·일 종일 | 50% |
| 중국 공휴일 종일 | 50% |

주간 오프피크 비율 `(17×5 + 24×2) / 168 = 133/168 ≈ 79.2%`

### 1.3 deepseek-flash 단가 (1M 토큰당 USD)

| 항목 | 피크 | 오프피크 |
|---|---|---|
| 입력 (cache hit) | $0.006 | $0.003 |
| 입력 (cache miss) | $0.30 | $0.15 |
| 출력 | $1.20 | $0.60 |

참고용. 인디케이터 표시에는 쓰지 않고 README에 둔다.

---

## 2. 공휴일 데이터

### 2.1 소스

[NateScarlet/holiday-cn](https://github.com/NateScarlet/holiday-cn) — 국무원 공고를 매일 자동 크롤링한다.

```
https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json
```

### 2.2 형식

```typescript
interface Holidays {
  year: number;
  papers: string[];       // 근거가 된 국무원 공고 URL
  days: {
    name: string;         // 节日名称
    date: string;         // ISO 8601
    isOffDay: boolean;    // true=휴일, false=대체근무일
  }[]
}
```

### 2.3 2026년 데이터 검증 (2026-10-20 확인)

`papers[]` = `https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm`

국무원 원문을 직접 받아 대조했고 **완전히 일치**했다.

| 명절 | 기간 |
|---|---|
| 元旦 | 2026-01-01 ~ 01-03 |
| 春节 | 2026-02-15 ~ 02-23 (9일) |
| 清明节 | 2026-04-04 ~ 04-06 |
| 劳动节 | 2026-05-01 ~ 05-05 |
| 端午节 | 2026-06-19 ~ 06-21 |
| 中秋节 | 2026-09-25 ~ 09-27 |
| 国庆节 | 2026-10-01 ~ 10-07 (7일) |

**대체근무일** (`isOffDay: false`) — 주말이지만 근무일로 지정된 날:

```
2026-01-04 (일)   元旦
2026-02-14 (토)   春节
2026-02-28 (토)   春节
2026-05-09 (토)   劳动节
2026-09-20 (일)   国庆节
2026-10-10 (토)   国庆节
```

### 2.4 2027년

2026-10-20 기준 **비어 있음**:

```json
{ "year": 2027, "papers": [], "days": [] }
```

국무원은 통상 매년 11월에 다음 해 공고를 낸다. 그 전까지는 2027년 데이터가 없다. 자동으로 채워지므로 수동 작업은 없다.

### 2.5 캐시 정책

```
cache/deepseek-peak/{year}.json

연도는 베이징 달력일(UTC+8) 기준으로 선택한다.
캐시 나이(TTL)는 파일의 LastWriteTimeUtc와 DateTime.UtcNow의 차이로 계산한다 — DST가 있는
로컬 벽시계 차이를 쓰면 전환일 전후로 1시간 어긋난다.

시작 시:
  파일이 있고 TTL 이내   → 재사용                       (TTL 기본 240시간 = 10일)
  파일이 있고 TTL 초과   → 기존 파일로 즉시 응답 + 백그라운드 갱신
  파일이 없음            → 동기 다운로드 시도(최대 10초), 실패하면 데이터 없이 진행

TTL 단축:
  해당 연도 papers[] 가 비어 있으면(미공고) TTL 을 min(설정값, 24시간) 으로 조인다.

갱신 규칙:
  동시 실행 1개 (스레드 작업). 실행 중이면 새로 띄우지 않는다.
  실패 시 1시간 쿨다운 후 재시도 (60초 폴링이 요청을 반복하지 않게).
  쓰기는 temp 파일 → 교체 로 atomic. 폴링 쪽이 반쯤 쓰인 JSON 을 읽지 않는다.
```

왜 10일인가: 평일/주말 규칙은 시간표가 고정이라 매번 계산으로 충분하고, 실제로 변하는 것은
공휴일 데이터뿐이다. 연간 공고(통상 11월)는 10일 안에 반드시 잡히고, 연중 임시휴일도 최대 10일
안에 반영된다. 트래픽은 4KB × 연 37회 수준이라 사실상 부하가 없다.

비동기인 이유: 갱신은 폴링을 막지 않는다. TTL 이 만료되면 그 호출은 **기존 캐시로 즉시 응답**하고,
갱신은 뒤에서 진행된다. 다음 폴링(최대 60초 뒤)이 새 데이터를 읽는다. 첫 실행만 동기로 기다린다.

놓쳤을 때의 방향: 공휴일을 놓치면 실제보다 **보수적으로 피크**를 표시한다(비용 손실 없음).
과금 손실이 나는 방향은 대체근무일(调休) 누락인데, 이는 연간 공고에만 등장하므로 10일 갱신으로 충분하다.

---

## 3. 판정 함수

### 3.1 시그니처

```powershell
function Get-PeakDecision {
    param(
        [datetime] $UtcNow,       # UTC 시각
        [object]   $HolidayData,  # 파싱된 {year, papers, days[]} 또는 $null
        [bool]     $TreatMakeupAsPeak = $true
    )
    # 반환: [pscustomobject]@{ IsPeak; Reason; Confidence }
}
```

`Reason` 값: `holiday` | `makeup-workday` | `weekend` | `weekday-peak` | `weekday-offpeak`
`Confidence` 값: `exact` | `estimated`

### 3.2 알고리즘

```
1. HolidayData 가 있고 해당 연도 papers[] 가 비어 있지 않으면:
     days[] 에서 $UtcNow.AddHours(8) 의 날짜(베이징 달력일)를 찾는다
       찾았고 isOffDay == true   → IsPeak=false, Reason='holiday',       Confidence='exact'
       찾았고 isOffDay == false  → TreatMakeupAsPeak ? (Peak, 'makeup-workday')
                                                      : (OffPeak, 'makeup-workday')
                                   Confidence='exact'
       못 찾음                   → 아래 2 로

2. 요일 판정
     토/일 → IsPeak=false, Reason='weekend', Confidence=(데이터있으면 exact, 없으면 estimated)

3. 시간 판정 (UTC)
     01:00 <= H < 04:00  또는  06:00 <= H < 10:00  → IsPeak=true,  'weekday-peak'
     그 외                                          → IsPeak=false, 'weekday-offpeak'
```

**중요**: 공휴일 판정은 **베이징 달력일(UTC+8)** 기준으로 한다. 원격 캘린더의 `date` 값은 중국 국무원
공고의 현지 날짜이므로, UTC 날짜로 대조하면 베이징 자정(UTC 16:00)에 시작·종료되는
대체근무일(调休)의 앞뒤 8시간이 어긋난다. 피크 시간대 자체는 공식 문서의 **UTC 고정 창**
(01:00–04:00, 06:00–10:00)을 그대로 쓴다.

```powershell
$beijing = $utc.AddHours(8)
$dateKey = $beijing.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
```

대체근무일을 피크로 보는 설정(`treatMakeupAsPeak`)에서는 해당 베이징 날짜의 00:00부터 24:00까지가
피크이므로, UTC 기준으로는 전날 16:00에 시작해 당일 16:00에 끝난다.

### 3.3 대체근무일 해석 — 가정

`isOffDay: false` 인 날을 피크로 볼지는 **검증되지 않은 판단**이다.

근거: 전국이 의무 근무하는 날이므로 서버 부하와 과금 정책이 평일에 준하게 운영될 가능성이 높다.

반대 근거: DeepSeek의 피크 정의는 "토·일 제외"만 명시하므로 주말이면 그냥 오프피크일 수 있다.

**결론**: 설정 플래그 `treatMakeupAsPeak` (기본 `true`)로 양쪽을 지원한다. 실측으로 판정이 불가능한 영역이므로 사용자가 선택한다.

---

## 4. 상태 출력

```powershell
[pscustomobject]@{
    Id           = 'deepseek-peak'
    Label        = 'DeepSeek 과금'
    Severity     = if ($IsPeak) { 'alert' } else { 'ok' }
    Headline     = if ($IsPeak) { 'PEAK · 100%' } else { 'OFF-PEAK · 50%' }
    Detail       = '→ 다음 구간까지 2h 14m'
    NextChangeAt = $nextChange
    NotifyText   = if ($IsPeak) {
                       '딥시크 피크 구간입니다 (100%). 대량 작업은 50% 구간까지 미루는 것을 검토하세요.'
                   } else {
                       '오프피크 구간입니다 (50%). 지금이 대량 작업 적기입니다.'
                   }
}
```

### 4.1 다음 전환 시각 계산

```
$cursor = $UtcNow 을 분 단위로 올림
최대 8일(11520분) 동안 1분씩 증가시키며
  Get-PeakDecision($cursor).IsPeak != 현재값 이 되는 첫 시각을 반환
```

8일 상한이면 연휴가 겹쳐도 충분하다. 분 단위 스캔이므로 구현이 단순하고, 1회 실행 비용은 무시할 수 있다.

### 4.2 Confidence 표시

`estimated` 이면 Detail 뒤에 `(추정)` 을 붙인다. 사용자가 판정 근거를 알 수 있게 한다.

### 4.3 로컬 시간대 표시

구간 정의는 **UTC 고정**이므로, 해외에서 접속하면 같은 순간이라도 로컬 시계에서의 위치가 달라진다.
예를 들어 미국 태평양(PDT, UTC-7)에서 UTC 화요일 피크(01–04, 06–10)는 이렇게 보인다.

| UTC (월–금) | PDT 로컬 |
|---|---|
| 01:00–04:00 | 전날 18:00–21:00 |
| 06:00–10:00 | 전날 23:00–다음날 03:00 |

요일 라벨까지 하루 밀린다(UTC 월요일 피크 = PDT 일요일 저녁). 그래서 **표를 통째로 시프트하지 않고
각 UTC 순간을 로컬로 변환**해야 한다. `Get-PeakLocalWindow` 가 그 계산을 담당한다.

```powershell
Get-PeakLocalWindow -UtcNow $utc -HolidayData $holiday -TimeZone ([TimeZoneInfo]::Local) -Count 3
# 반환: StartUtc, EndUtc, StartLocal, EndLocal, IsPeak 목록
# 첫 구간은 '지금 ~ 다음 전환', 이후 교대하는 구간이 이어진다.
```

- 변환 대상은 **기기 시간대**(`TimeZoneInfo.Local`) 또는 명시한 시간대다. 기기 시간대는 해외에서도
  KST 로 남아 있을 수 있으므로, IP 로 접속 지역을 확인해 두 번째 시각 뷰를 만든다(§4.4).
- DST 는 `TimeZoneInfo` 가 처리한다(서머타임 전후 자동 보정). 테스트: `tests\local-window.ps1` W5.
- UI 는 `NextChangeAt`(UTC)과 이 창 목록을 로컬로 렌더링한다. Detail 의 "다음 구간까지 2h 14m" 는 상대 시간이라 원래 시간대 무관이다.

### 4.4 기기 시간대 vs 접속 지역

노트북은 모바일과 달리 해외에서도 시간대가 자동으로 바뀌지 않는 경우가 많다(KST 로 고정해 두고 작업).
그래서 기기 시계만으로는 "현지 시각"을 알 수 없다. 이때 필요한 것이 접속 지역 확인이다.

```
하루 1회: https://ipinfo.io/json → { ip, country, city, timezone } → cache/region.json
          (24시간 캐시, 최대 5초, 실패 시 1시간 쿨다운 → 기기 시간대로 폴백)
```

`Get-PeakReferenceTimeZones` 가 두 시간대를 돌려준다.

```powershell
$ref = Get-PeakReferenceTimeZones -CacheDir $cache
# Device(KST) / Region(Asia/Seoul) / RegionId / Country / Label / Source / Mismatch
```

- `Mismatch` 는 **UTC 오프셋 차이**로 판정한다. 오프셋이 같으면(서울·도쿄) 시각이 같으므로 불일치가 아니다.
- 불일치면 UI 는 두 줄로 병기한다: `기기 10:00–13:00 (KST) · 현지 18:00–21:00 (PDT)`.
- **판정은 여전히 UTC 고정**이라 IP 는 피크 여부를 바꾸지 않는다. IP 는 표시용 힌트다.
- VPN·프록시는 IP 지역을 바꾼다 → 결과를 사실로 취급하지 않는다. 조회 실패·오프라인·미지 시간대는
  `Source = 'device'` 로 기기 시간대 폴백.
- 개인정보: IP 가 ipinfo.io 로 전송된다. 앱은 IP 를 저장하지 않고 국가·도시·시간대만 캐시한다.

---

## 5. 테스트

`tests/peak-decisions.ps1` — 표 기반 단위 테스트. **8개 전부 통과가 완료 조건.**

| # | 입력 (KST) | 기대 IsPeak | 근거 |
|---|---|---|---|
| 1 | 2026-10-20 01:00 | false | 평일 UTC 16시, 피크 창 밖 (실측 확인됨) |
| 2 | 2026-10-20 11:00 | true | 평일 KST 11시 = UTC 02시 |
| 3 | 2026-10-20 14:00 | false | 평일 KST 14시 = UTC 05시 |
| 4 | 2026-10-20 16:00 | true | 평일 KST 16시 = UTC 07시 |
| 5 | 2026-10-24 11:00 | false | 토요일 |
| 6 | 2026-10-01 11:00 | false | 국경절 (공휴일) |
| 7 | 2026-10-10 11:00 | true | 대체근무일 (토이나 근무) |
| 8 | 2027-01-05 11:00 | true | 데이터 없음 → 주말규칙 → 평일 피크 |

7번은 `treatMakeupAsPeak = true` 전제. `false` 로 바꾸면 기대값이 `false` 가 된다 — 두 경우 모두 테스트한다.

### 5.1 통합 테스트

1. `peak-tracker.ps1` 실행 → 인디케이터 창 표시 확인
2. `displayMode` 를 `peakOnly` 로 바꾸고 오프피크에 창이 사라지는지 확인
3. 알림 함수를 직접 호출해 풍선이 1회 뜨는지 확인
4. 창 드래그 → 종료 → 재시작 → 위치 복원 확인
5. 네트워크 차단 후 실행 → 캐시 또는 주말 규칙으로 동작 확인

---

## 6. 설정 섹션

```json
"providers": {
  "deepseek-peak": {
    "enabled": true,
    "treatMakeupAsPeak": true,
    "refreshHours": 240,
    "showEstimatedBadge": true
  }
}
```

---

## 7. 사용자가 알아야 할 한계

- **중국 공휴일은 한국 공휴일과 무관**하다. 규칙이 중국 기준이다.
- **2027년 데이터는 11월 공고 후** 채워진다. 그 전까지는 주말 규칙만 적용된다.
- **실시간 확인이 아니다.** 60초 주기로 갱신하므로 구간 경계에서 최대 1분 늦을 수 있다.
- **기기 시간대가 바뀌어도 판정은 동일하다.** 구간 정의가 UTC 고정이라 해외 출장·VPN 으로 로컬 시각이 달라져도
  피크 여부는 같은 순간에 같은 결과다(`tests\provider-state.ps1` S7). KST 표(§1.2)는 설명용이고,
  표시되는 시각만 로컬로 렌더링한다.
- **공인 IP 지역은 판정·과금에 영향이 없다.** 지역별 요금 구간이 없고 피크 창이 UTC 로 고정이므로
  IP 국가를 조회하지 않는다. 필요한 것은 기기 시간대뿐이고 그것도 UTC 변환으로 이미 처리된다.
- **요금을 조작하지 않는다.** 구간을 알려주는 것뿐이다.
