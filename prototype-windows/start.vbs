' DSH Notify — 콘솔 없이 상주 프로세스를 시작한다.
' pwsh -Sta 로 core.ps1 을 실행하고 즉시 반환한다.
Option Explicit

Dim fso, shell, root, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = root

command = "pwsh.exe -Sta -NoProfile -WindowStyle Hidden -File """ & root & "\core.ps1"""
shell.Run command, 0, False
