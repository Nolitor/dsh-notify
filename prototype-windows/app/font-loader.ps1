<#
.SYNOPSIS    BYO 폰트 로더 — 사용자 드롭 폰트를 저장하고 WPF FontFamily로 만든다.
.DESCRIPTION 기본은 시스템 폰트(Consolas/Segoe UI)다. 사용자가 .ttf/.otf를 창에 드롭하면
             앱 fonts 폴더(쓰기 불가 시 %LOCALAPPDATA%\DSH-Notify\fonts)에 격리 저장하고,
             MOTW를 제거한 뒤 FontFamily를 만들어 반환한다. 재시작 없이 UI에 재바인딩한다.
.CONTRACT    config.ps1 — Get-NotifyFontRoot/Test-NotifyDirectoryWritable
.INPUTS      Import-NotifyFontFile: Path, FontRoot; Get-NotifyStartupFont: FontRoot
.OUTPUTS     { FontFamily, FamilyName, Path } / FontFamily
.SIDE-EFFECTS 폰트 파일 복사·Unblock-File·이전 custom-* 정리.
.TESTS       tests\font-loader.ps1
.NOTES       폰트 파일은 시스템에 설치하지 않는다. 라이선스 책임은 사용자에게 있다.
#>

#region INDEX
#   Get-NotifyDefaultFontFamily   Consolas → Segoe UI 시스템 폰트
#   Test-NotifyFontFile           확장자/크기 검사
#   Get-NotifyFontFamilyFromFile  파일에서 패밀리명을 찾아 FontFamily 생성
#   Import-NotifyFontFile         드롭 파일을 격리 저장하고 FontFamily 반환
#   Get-NotifyStartupFont         저장된 custom-* 중 최신 폰트 로드
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing

if (-not (Get-Command Get-NotifyFontRoot -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'config.ps1')
}

$script:NotifyMaxFontBytes = 8 * 1024 * 1024
$script:NotifyFontExtensions = @('.ttf', '.otf')

function Get-NotifyDefaultFontFamily {
    foreach ($name in @('Consolas', 'Segoe UI', 'Segoe UI Variable', 'Arial')) {
        try {
            $family = [System.Windows.Media.FontFamily]::new($name)
            if (@($family.GetTypefaces()).Count -gt 0) { return $family }
        }
        catch { }
    }
    return [System.Windows.Media.FontFamily]::new('Segoe UI')
}

function Test-NotifyFontFile {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($script:NotifyFontExtensions -notcontains $extension) { return $false }
    try {
        if ((Get-Item -LiteralPath $Path).Length -gt $script:NotifyMaxFontBytes) { return $false }
    }
    catch { return $false }
    return $true
}

function Get-NotifyFontFamilyFromFile {
    param([string] $Path)

    if (-not (Test-NotifyFontFile -Path $Path)) { throw "지원하지 않는 폰트 파일입니다: $Path" }

    Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue

    $familyName = ''
    $collection = $null
    try {
        $collection = New-Object System.Drawing.Text.PrivateFontCollection
        $collection.AddFontFile($Path)
        if ($collection.Families.Count -gt 0) { $familyName = $collection.Families[0].Name }
    }
    catch {
        $familyName = ''
    }
    finally {
        if ($null -ne $collection) { $collection.Dispose() }
    }

    if ([string]::IsNullOrWhiteSpace($familyName)) {
        $folder = [Uri]::new((Split-Path -Parent $Path) + [IO.Path]::DirectorySeparatorChar)
        $families = @([System.Windows.Media.Fonts]::GetFontFamilies($folder))
        if ($families.Count -gt 0) {
            $familyName = @($families[0].FamilyNames.Values)[0]
        }
    }
    if ([string]::IsNullOrWhiteSpace($familyName)) { throw "폰트 패밀리 이름을 찾지 못했습니다: $Path" }

    $uri = [Uri]::new($Path)
    $fontFamily = [System.Windows.Media.FontFamily]::new($uri, "./#$familyName")
    if (@($fontFamily.GetTypefaces()).Count -eq 0) { throw "WPF가 폰트를 로드하지 못했습니다: $familyName" }

    return [pscustomobject]@{
        FontFamily = $fontFamily
        FamilyName = $familyName
        Path       = $Path
    }
}

function Import-NotifyFontFile {
    param(
        [string] $Path,
        [string] $FontRoot
    )

    if (-not (Test-NotifyFontFile -Path $Path)) { throw "TTF/OTF 폰트만 드롭할 수 있습니다." }
    if ([string]::IsNullOrWhiteSpace($FontRoot)) { throw "폰트 저장 경로가 없습니다." }

    $customDir = Join-Path $FontRoot 'custom'
    if (-not (Test-Path -LiteralPath $customDir)) { New-Item -ItemType Directory -Path $customDir -Force | Out-Null }

    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $name = 'custom-' + (Get-Date).ToString('yyyyMMdd-HHmmssfff') + $extension
    $destination = Join-Path $customDir $name
    Copy-Item -LiteralPath $Path -Destination $destination -Force
    Unblock-File -LiteralPath $destination -ErrorAction SilentlyContinue

    try {
        $font = Get-NotifyFontFamilyFromFile -Path $destination
    }
    catch {
        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        throw
    }

    Get-ChildItem -LiteralPath $customDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'custom-*' -and $_.FullName -ne $destination } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    return $font
}

function Get-NotifyStartupFont {
    param([string] $FontRoot)

    if (-not [string]::IsNullOrWhiteSpace($FontRoot)) {
        $customDir = Join-Path $FontRoot 'custom'
        if (Test-Path -LiteralPath $customDir) {
            $latest = Get-ChildItem -LiteralPath $customDir -File -ErrorAction SilentlyContinue |
                Where-Object { $script:NotifyFontExtensions -contains $_.Extension.ToLowerInvariant() } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($null -ne $latest) {
                try { return Get-NotifyFontFamilyFromFile -Path $latest.FullName }
                catch { }
            }
        }
    }
    return [pscustomobject]@{
        FontFamily = Get-NotifyDefaultFontFamily
        FamilyName = 'system'
        Path       = ''
    }
}
