# 글로벌 타임존·중국 공휴일 실측 보고서

> 상태: active · 최종 갱신: 2026-10-23 · git: main · 상위: [deepseek-peak-spec.md](./deepseek-peak-spec.md)

- 대상: `providers/deepseek-peak.ps1`, `ui/presenter.ps1`, `config.ps1`
- 검증일: 2026-10-23 (Asia/Seoul)
- 공식 기준: [DeepSeek Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing) (2026-10-23 fetch)

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 결론 | UTC 절대 판정, 베이징 날짜 보정, DST 무관 카운트다운 |
| 2 | 공식 스케줄 | 2026 공식 문서와 사용자 전제의 차이 |
| 3 | 코드 분석 | 공휴일 날짜·10일 TTL·카운트다운·로컬 표기 경로 |
| 4 | 3개 시간대 매트릭스 | 서울·런던·뉴욕 44개 실측 |
| 5 | 발견·수정 | 대체근무일 8시간 경계 오차와 UTC TTL |
| 6 | 잔여 리스크 | 연도 경계, 대체근무일 가정, 실제 OS 시간대 |
| 7 | 재현 | 테스트 명령과 결과 |

---

## 1. 결론

- **공휴일 판정은 이제 베이징 달력일(UTC+8) 기준**이다. 이전에는 UTC 날짜를 썼기 때문에
  베이징 자정에 시작·끝나는 **대체근무일(调休)** 경계에서 8시간 오차가 있었다.
- **일반 피크/오프피크 판정과 카운트다운은 UTC 절대 시각**으로 계산된다. 사용자 로컬 시각을
  날짜 키로 쓰거나 KST를 하드코딩하지 않는다.
- **로컬 표기만 `TimeZoneInfo`**에 위임한다. 런던 BST, 뉴욕 EDT/EST 전환에서도 동일 UTC
  시각의 상태·다음 전환·남은 초는 서울과 완전히 같다.
- 사용자 전제의 **“매일 00:30–08:30 UTC+8 오프피크”는 2026 공식 문서와 다르다.** 공식 문서는
  피크를 `01:00–04:00`, `06:00–10:00 UTC` 평일(중국 공휴일 제외)로 정의한다. 현재 코드/스펙은
  공식 문서를 따른다.

## 2. 공식 스케줄과 전제 차이

공식 문서 원문(2026-10-23 확인):

> Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday, excluding Chinese
> public holidays. All other hours are off-peak, including weekends and Chinese public holidays in full.

| 구분 | UTC | 베이징(UTC+8) | 비고 |
|---|---|---|---|
| 피크 1 | 01:00–04:00 | 09:00–12:00 | 평일, 공휴일 제외 |
| 피크 2 | 06:00–10:00 | 14:00–18:00 | 평일, 공휴일 제외 |
| 그 외 | — | — | 주말·중국 공휴일 포함 오프피크 |

따라서 “베이징 00:30–08:30이 매일 오프피크”라는 전제는 현재 공식 스케줄과 맞지 않는다.
현재 코드는 공식 스케줄을 구현하고 있으며, 이 보고서의 테스트도 공식 스케줄을 기준으로 한다.
만약 00:30–08:30 베이징 창을 의도한 별도 요금제라면 스케줄 자체를 교체해야 하며, 이는
이번 타임존 보정과 별개의 제품 결정이다.

## 3. 코드 분석

### 3.1 공휴일 날짜·연도

`Get-PeakDecision`은 입력을 UTC로 정규화한 뒤 **UTC+8 달력일**로 원격 캘린더의 `date`와
대조한다. `Get-State`도 같은 기준으로 연도 캐시를 고른다.

```powershell
$utc = ConvertTo-Utc -Value $UtcNow
$beijing = $utc.AddHours(8)
$year = $beijing.Year
$dateKey = $beijing.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
```

피크 시간 창은 공식 문서대로 **UTC 시각**의 `01–04`, `06–10`을 쓴다. 즉 “날짜는 베이징,
시간 창은 UTC”가 올바른 조합이다.

### 3.2 10일 캐시 TTL

- 캐시 파일 나이: `DateTime.UtcNow - LastWriteTimeUtc`로 계산한다.
- 재시도 쿨다운: 마지막 시도도 `DateTime.UtcNow`로 기록한다.
- 이전 구현은 `Get-Date`와 로컬 `LastWriteTime`의 벽시계 차이를 썼다. DST 전환일에는
  TTL이 최대 1시간 일찍/늦게 만료될 수 있었으나, 12시간 오차는 아니었다.
- 연도 키는 베이징 연도다. UTC 연도와 베이징 연도가 다른 16:00–24:00 UTC 구간은
  피크 창 밖이라 상태에는 영향이 없지만, 데이터 선택의 의미를 맞추기 위해 보정했다.

### 3.3 카운트다운

- `Get-State`: `$Now.ToUniversalTime()`으로 절대 UTC를 만든다.
- `Format-PeakSpan`: `NextChangeAt(UTC) - UtcNow(UTC)`의 `TimeSpan`.
- `presenter.ps1`: `ConvertTo-ContractUtc`로 양쪽을 UTC로 맞춘 뒤 초 단위로 내림.
- KST 01:30, UTC+9 고정값 같은 하드코딩은 없다.

### 3.4 로컬 표기

- `Format-RegionWindow`: `TimeZoneInfo.ConvertTimeFromUtc`와 `GetUtcOffset` 사용.
- `Get-PeakLocalWindow`: `TimeZoneInfo.ConvertTimeFromUtc` 사용.
- 수동 `AddHours(9)`/`AddHours(-4)` 같은 오프셋 가감은 표시 경로에 없다.

## 4. 3개 시간대 매트릭스

`tests/timezone-matrix.ps1`은 같은 UTC 시각을 서울·런던·뉴욕의 로컬 `DateTime`으로 변환한 뒤
다시 UTC로 복원해, 다음 네 값을 비교한다.

1. `Get-PeakDecision().IsPeak`
2. `Get-PeakNextChange()`의 UTC 틱
3. `Format-PeakTimer()`의 `HH:MM:SS`
4. `Format-PeakSpan()`의 남은 시간

### 4.1 대표 실측값

| UTC | 상태 | 다음 전환(UTC) | 남은 시간 | 서울 | 런던 | 뉴욕 |
|---|---|---|---|---|---|---|
| 2026-10-01 01:00 | Off-Peak (국경절) | 10-08 01:00 | 168:00:00 | 10:00 | 02:00 BST | 09-30 21:00 EDT |
| 2026-10-08 01:00 | Peak | 10-08 04:00 | 03:00:00 | 10:00 | 02:00 BST | 10-07 21:00 EDT |
| 2026-10-09 16:00 | Peak (대체근무일) | 10-10 16:00 | 24:00:00 | 10-10 01:00 | 17:00 BST | 10-09 12:00 EDT |
| 2026-10-10 16:00 | Off-Peak (주말) | 10-12 01:00 | 33:00:00 | 10-11 01:00 | 17:00 BST | 10-10 12:00 EDT |
| 2026-10-20 10:00 | Off-Peak | 10-21 01:00 | 15:00:00 | 19:00 | 11:00 BST | 06:00 EDT |

모든 행에서 세 시간대의 상태·다음 전환·타이머 문자열이 **완전히 동일**했다.
(테이블의 런던/뉴욕 로컬 값은 `TimeZoneInfo` 변환 결과이며, DST 오프셋은 아래와 같다.)

### 4.2 DST 오프셋

| UTC | 런던 | 뉴욕 | 서울 |
|---|---:|---:|---:|
| 2026-01-15 12:00 | +0 | −5 | +9 |
| 2026-03-29 00:59:59 | +0 | −4 | +9 |
| 2026-03-29 01:00 | +1 (BST) | −4 | +9 |
| 2026-07-15 12:00 | +1 | −4 (EDT) | +9 |
| 2026-10-25 00:59:59 | +1 | −4 | +9 |
| 2026-10-25 01:00 | +0 | −4 | +9 |
| 2026-11-01 05:59:59 | +0 | −4 | +9 |
| 2026-11-01 06:00 | +0 | −5 (EST) | +9 |

### 4.3 테스트 결과

```
timezone-matrix: 44 passed / 0 failed
```

## 5. 발견·수정

### 5.1 대체근무일 8시간 경계 오차 (수정)

수정 전에는 공휴일 날짜를 **UTC 날짜**로 찾았다. 국경절(휴일) 자체는 피크 창 밖이라 상태가
우연히 같았지만, 2026-10-10(토) 대체근무일은 **종일 피크**로 처리되므로 경계가 어긋났다.

| 시각(UTC) | 베이징 | 수정 전 | 수정 후 |
|---|---|---|---|
| 2026-10-09 15:59:59 | 10-09 23:59:59 | Off-Peak | Off-Peak |
| 2026-10-09 16:00 | 10-10 00:00 | Off-Peak (8시간 늦음) | **Peak** |
| 2026-10-10 15:59:59 | 10-10 23:59:59 | Peak | **Peak** |
| 2026-10-10 16:00 | 10-11 00:00 | Peak (8시간 늦게 끝남) | **Off-Peak** |

2026-09-28~10-12를 1분 단위(20,160분)로 전수 비교한 결과:

| 버전 | 상태 불일치 |
|---|---:|
| 수정 전 | **960분** (대체근무일 시작 8h + 종료 8h) |
| 수정 후 | **0분** |

### 5.2 10일 TTL의 로컬 벽시계 (수정)

`Get-HolidayData`의 `Get-Date - LastWriteTime`을 `DateTime.UtcNow - LastWriteTimeUtc`로 바꿨다.
재시도 쿨다운도 UTC로 통일했다. DST 전환일의 1시간 오차를 제거했다.

### 5.3 12시간 오차 주장에 대한 판정

현재 코드는 공휴일 날짜에 로컬 시각(예: 뉴욕 `DateTime.Now`)을 쓴 적이 없다. 따라서
“뉴욕 사용자가 12시간 늦게 적용”되는 경로는 **없다.** 문제는 로컬 시각이 아니라 **UTC 날짜**를
썼다는 점이었고, 그 영향은 대체근무일 경계의 **8시간**이었다.

## 6. 잔여 리스크

1. **연도 경계 데이터**: `Get-State`는 베이징 연도 캐시를 하나만 읽는다. 12월 31일 밤에서
   1월 1일로 넘어가는 8일 스캔에서 다음 해 공휴일 데이터가 없으면 `estimated`로 강등된다.
   2027년 공고 전에는 이 한계가 남는다.
2. **대체근무일 가정**: `treatMakeupAsPeak`는 공식 문서에 명시되지 않은 제품 가정이다.
   기본값 `true`는 “전국 의무 근무일은 피크”라는 해석이며, 실제 서버 과금과 다를 수 있다.
3. **실제 OS 시간대**: 테스트는 `TimeZoneInfo` 변환 경계를 모킹했다. 실제 Windows에서
   `Get-Date`가 반환하는 `Kind=Local`과 `ToUniversalTime()`의 OS 처리는 별도 스모크에서
   확인해야 한다. 코드는 수동 오프셋을 쓰지 않고 .NET에 위임한다.
4. **공식 스케줄 변경**: 이 보고서는 2026-10-23 공식 문서를 기준으로 한다. 요금제가 바뀌면
   UTC 피크 창과 테스트 픽스처를 함께 갱신해야 한다.

## 7. 재현

```powershell
pwsh -NoProfile -File tests\timezone-matrix.ps1
pwsh -NoProfile -File tests\peak-decisions.ps1
pwsh -NoProfile -File tests\run-all.ps1
pwsh -NoProfile -File tests\docs-contract.ps1
```

실측 결과:

| 명령 | 결과 |
|---|---|
| `tests\timezone-matrix.ps1` | 44 passed / 0 failed |
| `tests\peak-decisions.ps1` | 23 passed / 0 failed |
| `tests\run-all.ps1` | 23 files, 23 passed, 0 failed |
| `tests\docs-contract.ps1` | 58 files PASS |
