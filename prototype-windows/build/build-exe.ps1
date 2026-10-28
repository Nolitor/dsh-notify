<#
.SYNOPSIS    DSH Notify 전체를 단일 exe(래퍼)로 빌드한다.
.DESCRIPTION 스크립트·아이콘·폰트를 zip 페이로드로 묶고, .NET Framework csc 로
             작은 C# 런처에 리소스로 박는다. 실행 시 %LOCALAPPDATA%\DSH Notify\runtime 에
             풀어서 숨김 pwsh(-Sta)로 core.ps1 을 띄운다.
             PowerShell 7 이 설치되어 있어야 한다(스크립트 실행 엔진).
.CONTRACT    core.ps1, config.ps1, providers\, ui\, notify\
.INPUTS      -Out(기본 저장소 루트의 DSH-Notify.exe)
.OUTPUTS     단일 exe 파일
.SIDE-EFFECTS 임시 스테이징/zip 생성·삭제, exe 쓰기.
.TESTS       수동: exe 실행 후 화면 카드 확인
.NOTES       csc 는 Windows 내장 .NET Framework 4.x 컴파일러를 쓴다(별도 SDK 불필요).
             페이로드 버전이 바뀌면 런타임 폴더를 다시 푼다(설정 파일은 유지).
#>

param(
    [string] $Out = ''
)

#region INDEX
#   (main)  스테이징 → zip → C# 런처 생성 → csc 컴파일
#endregion

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Out)) { $Out = Join-Path $repoRoot 'DSH-Notify.exe' }

$stage = Join-Path $env:TEMP ('dsh-exe-stage-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $env:TEMP ('dsh-payload-' + [guid]::NewGuid().ToString('N') + '.zip')
$launcher = Join-Path $env:TEMP ('dsh-launcher-' + [guid]::NewGuid().ToString('N') + '.cs')

New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'ui') -Force | Out-Null

function Copy-IfExists([string] $Path, [string] $Destination) {
    if (Test-Path -LiteralPath $Path) { Copy-Item -LiteralPath $Path -Destination $Destination -Force }
}

Copy-IfExists (Join-Path $repoRoot 'core.ps1') $stage
Copy-IfExists (Join-Path $repoRoot 'config.ps1') $stage
Copy-Item (Join-Path $repoRoot 'app') (Join-Path $stage 'app') -Recurse -Force
Copy-Item (Join-Path $repoRoot 'providers') (Join-Path $stage 'providers') -Recurse -Force
Copy-Item (Join-Path $repoRoot 'notify') (Join-Path $stage 'notify') -Recurse -Force
foreach ($file in @(Get-ChildItem (Join-Path $repoRoot 'ui') -Filter '*.ps1' -File)) {
    Copy-Item $file.FullName (Join-Path $stage 'ui') -Force
}
Copy-Item (Join-Path $repoRoot 'ui\assets') (Join-Path $stage 'ui\assets') -Recurse -Force
Copy-Item (Join-Path $repoRoot 'ui\icons') (Join-Path $stage 'ui\icons') -Recurse -Force

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payload -Force
$version = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.Substring(0, 12)

$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

class DshNotifyLauncher
{
    [STAThread]
    static void Main(string[] args)
    {
        try
        {
            string root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "DSH Notify",
                "runtime");
            string versionFile = Path.Combine(root, ".payload-version");
            string version = "__VERSION__";

            bool needsExtract = true;
            if (Directory.Exists(root) && File.Exists(versionFile))
            {
                try { needsExtract = File.ReadAllText(versionFile).Trim() != version; }
                catch { needsExtract = true; }
            }

            if (needsExtract)
            {
                Directory.CreateDirectory(root);
                using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
                {
                    if (stream == null) throw new InvalidOperationException("payload.zip resource missing");
                    using (ZipArchive archive = new ZipArchive(stream, ZipArchiveMode.Read))
                    {
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            if (entry.Name.Length == 0) continue;
                            string destination = Path.Combine(root, entry.FullName.Replace('/', Path.DirectorySeparatorChar));
                            string directory = Path.GetDirectoryName(destination);
                            if (!Directory.Exists(directory)) Directory.CreateDirectory(directory);
                            entry.ExtractToFile(destination, true);
                        }
                    }
                }
                File.WriteAllText(versionFile, version);
            }

            string core = Path.Combine(root, "core.ps1");
            string arguments = "-Sta -NoProfile -WindowStyle Hidden -File \"" + core + "\"";
            foreach (string arg in args) arguments += " \"" + arg.Replace("\"", "\\\"") + "\"";
            ProcessStartInfo info = new ProcessStartInfo("pwsh.exe", arguments);
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            Process.Start(info);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "DSH Notify");
        }
    }
}
'@
$source = $source.Replace('__VERSION__', $version)
Set-Content -LiteralPath $launcher -Value $source -Encoding UTF8

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "csc.exe 를 찾지 못했습니다: $csc" }

& $csc /nologo /target:winexe /out:$Out /resource:$payload `
    /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /r:System.Windows.Forms.dll $launcher
if ($LASTEXITCODE -ne 0) { throw "csc 컴파일 실패 (exit $LASTEXITCODE)" }

Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $launcher -Force -ErrorAction SilentlyContinue

Write-Host "OK: $Out ($([Math]::Round((Get-Item $Out).Length / 1KB)) KB, payload $version)"
exit 0
