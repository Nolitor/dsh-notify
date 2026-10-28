// DSH Notify — Zero-Flicker launcher (Windows Script Host / JScript)
// wscript.exe is a GUI-subsystem host: it creates no console window.
// VBScript is disabled on some managed PCs, so this launcher uses JScript,
// which is still provided by the built-in Windows Script Host.
//
// High-integrity shells cannot receive Explorer's OLE drops (UIPI). If this
// launcher was started elevated, it re-launches itself through Explorer via a
// temporary .lnk, which yields a Medium-integrity wscript.exe. The --medium
// flag prevents an infinite relaunch loop.
(function () {
    var fso = new ActiveXObject("Scripting.FileSystemObject");
    var shell = new ActiveXObject("WScript.Shell");
    var root = fso.GetParentFolderName(WScript.ScriptFullName);
    var temp = fso.GetSpecialFolder(2);
    var medium = false;
    var dryRun = false;

    for (var i = 0; i < WScript.Arguments.length; i++) {
        var arg = String(WScript.Arguments(i)).toLowerCase();
        if (arg === "--medium") { medium = true; }
        if (arg === "--dry-run") { dryRun = true; }
    }

    if (dryRun) { WScript.Quit(0); }

    if (!medium) {
        var probe = temp + "\\dsh-notify-integrity-" + (new Date().getTime()) + ".txt";
        try {
            shell.Run('cmd.exe /d /c whoami /groups > "' + probe + '"', 0, true);
            var input = fso.OpenTextFile(probe, 1, false);
            var text = input.ReadAll();
            input.Close();
            fso.DeleteFile(probe, true);

            if (text.indexOf("S-1-16-12288") >= 0) {
                var shortcutPath = temp + "\\DSH-Notify-Medium.lnk";
                var shortcut = shell.CreateShortcut(shortcutPath);
                shortcut.TargetPath = shell.ExpandEnvironmentStrings("%WINDIR%") + "\\System32\\wscript.exe";
                shortcut.Arguments = '//B //NoLogo "' + WScript.ScriptFullName + '" --medium';
                shortcut.WorkingDirectory = root;
                shortcut.WindowStyle = 7;
                shortcut.Description = "DSH Notify medium-integrity launcher";
                shortcut.Save();
                shell.Run('explorer.exe "' + shortcutPath + '"', 0, false);
                WScript.Quit(0);
            }
        }
        catch (e) {
            // Integrity probe is best-effort. Normal Explorer launches are Medium.
        }
    }

    var core = root + "\\core.ps1";
    if (!fso.FileExists(core)) { core = root + "\\app\\core.ps1"; }
    if (!fso.FileExists(core)) {
        shell.Popup("DSH Notify: core.ps1 not found.", 8, "DSH Notify", 16);
        WScript.Quit(1);
    }

    var command = '"pwsh.exe" -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File "' + core + '"';
    try {
        shell.Run(command, 0, false);
        WScript.Quit(0);
    }
    catch (e2) {
        shell.Popup("PowerShell 7 is required. Install with: winget install Microsoft.PowerShell", 8, "DSH Notify", 48);
        WScript.Quit(1);
    }
})();
