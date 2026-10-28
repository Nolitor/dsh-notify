<#
.SYNOPSIS    윈도 네이티브 토스트(Windows.UI.Notifications) 생성·표시를 검증한다.
.DESCRIPTION XML 생성은 순수 함수라 문자열 이스케이프·템플릿을 결정적으로 검사하고,
             표시 경로는 -DryRun 으로 팝업 없이 배관만 확인한다. 실제 팝업은 수동 스모크로 확인한다.
.CONTRACT    notify\toast.ps1 — New-ToastXml, Send-WindowsToast
.INPUTS      없음. notify\toast.ps1 을 dot-source 한다.
.OUTPUTS     PASS/FAIL 리포트. 종료코드 0 = 전부 통과, 1 = 실패 있음.
.SIDE-EFFECTS 없음 (-DryRun 만 사용).
.TESTS       Windows 10/11 ToastGeneric XML
.NOTES       PS7 은 WinRT 타입을 직접 못 읽는다 — 표시는 Windows PowerShell 5.1 자식 프로세스가 담당.
#>

#region INDEX
#   Assert-Contains  부분 문자열 검사
#   (main)           T1~T4 XML 생성, CLI T5~T6 dry-run
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$toastPath = Join-Path $repoRoot 'notify\toast.ps1'
$cliPath = Join-Path $repoRoot 'notify\send-toast.ps1'

if (-not (Test-Path -LiteralPath $toastPath)) {
    Write-Host 'RED: notify\toast.ps1 이 없습니다.'
    exit 1
}
. $toastPath

$script:Pass = 0
$script:Fail = 0

function Assert-Contains {
    param([string] $Haystack, [string] $Needle, [string] $Label)

    if ($Haystack.Contains($Needle)) { $script:Pass++; Write-Host "PASS $Label"; return }
    $script:Fail++
    Write-Host "FAIL $Label — '$Needle' 없음"
}

# T1 기본 템플릿
$xml = New-ToastXml -Title 'DSH Notify' -Body '피크 구간입니다'
Assert-Contains -Haystack $xml -Needle 'binding template="ToastGeneric"' -Label 'T1 ToastGeneric 바인딩'
Assert-Contains -Haystack $xml -Needle '<text>DSH Notify</text>' -Label 'T1 제목 텍스트'
Assert-Contains -Haystack $xml -Needle '<text>피크 구간입니다</text>' -Label 'T1 본문 텍스트'

# T2 XML 이스케이프
$xml = New-ToastXml -Title 'A&B <x>' -Body 'q "z"'
Assert-Contains -Haystack $xml -Needle 'A&amp;B &lt;x&gt;' -Label 'T2 제목 이스케이프'
Assert-Contains -Haystack $xml -Needle 'q "z"' -Label 'T2 본문 텍스트 보존'

# T3 빈 본문은 text 요소 생략
$xml = New-ToastXml -Title 'Only title' -Body ''
Assert-Contains -Haystack $xml -Needle '<text>Only title</text>' -Label 'T3 제목만'
if ($xml.Contains('<text></text>')) { $script:Fail++; Write-Host 'FAIL T3 빈 본문 요소가 남음' }
else { $script:Pass++; Write-Host 'PASS T3 빈 본문 요소 없음' }

# T4 tostring 재사용 시 XML 재파싱 가능
$doc = New-Object System.Xml.XmlDocument
$doc.LoadXml($xml)
Assert-Contains -Haystack $doc.OuterXml -Needle 'Only title' -Label 'T4 유효한 XML'

# T5 CLI dry-run (PS7 → 5.1 스폰 없이 XML 만 반환)
$out = & pwsh -NoProfile -NoLogo -File $cliPath -Title '제목' -Body '본문' -DryRun 2>&1
$code = $LASTEXITCODE
if ($code -eq 0 -and ($out -join "`n").Contains('ToastGeneric')) { $script:Pass++; Write-Host 'PASS T5 CLI dry-run' }
else { $script:Fail++; Write-Host "FAIL T5 CLI dry-run — exit=$code out=$($out -join ' ')" }

# T6 CLI dry-run 은 표시하지 않음 (XML 문자열만 반환)
$out2 = & pwsh -NoProfile -NoLogo -File $cliPath -Title 'X' -Body 'Y' -DryRun 2>&1
if (($out2 -join "`n").Trim().StartsWith('<toast')) { $script:Pass++; Write-Host 'PASS T6 CLI 출력은 XML 단독' }
else { $script:Fail++; Write-Host "FAIL T6 CLI 출력 형식 — $($out2 -join ' ')" }

Write-Host ''
Write-Host "toast: $($script:Pass) passed / $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
