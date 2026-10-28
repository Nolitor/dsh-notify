<#
.SYNOPSIS    저장소의 문서·스크립트가 헤더와 스켈레톤 인덱스 규약을 지켰는지 검사한다.
.DESCRIPTION README.md 와 docs\*.md 는 '> 상태:' 헤더 줄과 '## 인덱스' 절을,
             providers\*.ps1 와 tests\*.ps1 는 comment-based help 의 .SYNOPSIS 와
             '#region INDEX' 를 가져야 한다. 위반 시 파일과 사유를 출력하고 종료코드 1.
.CONTRACT    docs\WORK-PROTOCOL.md §2 (헤더 + 스켈레톤 인덱스), §3 (자동 검사)
.INPUTS      없음. $PSScriptRoot 기준으로 저장소 루트를 역산한다.
.OUTPUTS     표준 출력 리포트. 종료코드 0 = 전부 준수, 1 = 위반 있음.
.SIDE-EFFECTS 없음 (읽기 전용).
.TESTS       tests\run-all.ps1 이 이 파일을 실행한다.
.NOTES       규약 v1 — 2026-10-20
#>

#region INDEX
#   Test-MarkdownContract  md 헤더·인덱스 검사            docs\*.md, README.md
#   Test-ScriptContract    ps1 헤더·INDEX region 검사     providers\*.ps1, tests\*.ps1
#   Get-ContractTargets    검사 대상 파일 수집            없음
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-ContractTargets {
    $markdown = @(Get-ChildItem -Path (Join-Path $repoRoot 'docs') -Filter '*.md' -File -ErrorAction SilentlyContinue)
    $readme = Join-Path $repoRoot 'README.md'
    if (Test-Path $readme) { $markdown = @($markdown) + @(Get-Item $readme) }

    $scripts = @()
    foreach ($dir in @('providers', 'tests', 'notify', 'ui', 'build')) {
        $path = Join-Path $repoRoot $dir
        if (Test-Path $path) {
            $scripts = @($scripts) + @(Get-ChildItem -Path $path -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
        }
    }
    $scripts = @($scripts) + @(Get-ChildItem -Path $repoRoot -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

    return [pscustomobject]@{
        Markdown = @($markdown | Sort-Object FullName)
        Scripts  = @($scripts | Sort-Object FullName)
    }
}

function Test-MarkdownContract {
    param([System.IO.FileInfo] $File)

    $lines = @(Get-Content -LiteralPath $File.FullName -Encoding UTF8)
    $problems = @()

    if ($lines.Count -lt 2 -or -not $lines[0].StartsWith('# ')) {
        $problems += 'h1 제목 없음'
        return $problems
    }

    $headerLine = $null
    $limit = [Math]::Min($lines.Count, 9)
    for ($i = 1; $i -lt $limit; $i++) {
        if ($lines[$i] -match '^>\s*상태:\s*\S+') { $headerLine = $i; break }
    }
    if ($null -eq $headerLine) { $problems += "'> 상태:' 헤더 줄이 제목 후 8줄 안에 없음" }

    $hasIndex = @($lines | Where-Object { $_ -match '^##\s+인덱스\s*$' }).Count -gt 0
    if (-not $hasIndex) { $problems += "'## 인덱스' 절 없음" }

    return $problems
}

function Test-ScriptContract {
    param([System.IO.FileInfo] $File)

    $raw = Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8
    $problems = @()

    $block = [regex]::Match($raw, '(?s)<#(.*?)#>')
    if (-not $block.Success) {
        $problems += '<# ... #> 헤더 블록 없음'
    }
    elseif ($block.Groups[1].Value -notmatch '(?m)^\s*\.SYNOPSIS\b') {
        $problems += '헤더 블록에 .SYNOPSIS 없음'
    }

    if ($raw -notmatch '(?m)^#region INDEX\s*$') {
        $problems += "'#region INDEX' 없음"
    }

    return $problems
}

$targets = Get-ContractTargets
$violations = @()
$checked = 0

foreach ($file in $targets.Markdown) {
    $checked++
    foreach ($problem in (Test-MarkdownContract -File $file)) {
        $violations += [pscustomobject]@{ File = $file.FullName; Problem = $problem }
    }
}

foreach ($file in $targets.Scripts) {
    $checked++
    foreach ($problem in (Test-ScriptContract -File $file)) {
        $violations += [pscustomobject]@{ File = $file.FullName; Problem = $problem }
    }
}

if ($violations.Count -gt 0) {
    foreach ($v in $violations) {
        $rel = $v.File.Substring($repoRoot.Length).TrimStart('\')
        Write-Host "FAIL docs-contract: $rel — $($v.Problem)"
    }
    Write-Host "FAIL docs-contract: $($violations.Count) violation(s) / $checked file(s) checked"
    exit 1
}

Write-Host "PASS docs-contract: $checked file(s), headers and indexes present"
exit 0
