<#
.SYNOPSIS    새 provider 를 작성할 때 복사해서 쓰는 빈 틀.
.DESCRIPTION providers\<id>.ps1 로 복사한 뒤 Get-State 를 구현한다. UI 는 손대지 않는다.
.CONTRACT    docs\2026-10-20-dsh-notify-design.md §2.2 (provider 계약)
.INPUTS      Now: 로컬 시각, Config: config.json 의 providers.<id> 섹션, CacheDir: 캐시 절대 경로
.OUTPUTS     Id, Label, Severity(ok|warn|alert), Headline, Detail, NextChangeAt, NotifyText
.SIDE-EFFECTS 구현에 따라 캐시를 쓸 수 있다. 실패는 던지지 말고 상위 로더가 격리한다.
.TESTS       새 provider 를 만들면 tests\<id>-state.ps1 을 함께 만든다.
.NOTES       docs\WORK-PROTOCOL.md §2.2 (ps1 헤더 규칙)
#>

#region INDEX
#   Get-State   provider 계약 진입점 — 상태 객체 1건 반환
#endregion

function Get-State {
    param(
        [datetime] $Now,
        [hashtable] $Config,
        [string]   $CacheDir
    )

    # 1. 헤더·인덱스를 먼저 채우고, 그 다음 이 주석을 지우며 로직을 쓴다.
    # 2. 판정이 불확실하면 안전한 쪽으로 강등하고 Detail 에 근거를 노출한다.
    # 3. 실패해도 throw 하지 않는다 — 상위 로더가 이 provider 만 건너뛴다.

    return [pscustomobject]@{
        Id           = 'CHANGE-ME'
        Label        = 'CHANGE-ME'
        Severity     = 'ok'                  # ok | warn | alert
        Headline     = 'CHANGE-ME'
        Detail       = ''
        NextChangeAt = $null
        NotifyText   = ''
    }
}
