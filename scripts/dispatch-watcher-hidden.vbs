' ADR-005 headless wrapper.
'
' Scheduled Task invokes this VBS via wscript.exe, which has no console.
' The VBS then launches powershell.exe with SW_HIDE (the "0" argument to
' Run), producing a fully headless invocation chain -- no console window,
' no focus steal, even under LogonType Interactive.
'
' Invoked as:  wscript.exe //nologo dispatch-watcher-hidden.vbs

Option Explicit

Dim oShell, oFSO, sScriptDir, sWatcher, sCmd

Set oShell = CreateObject("WScript.Shell")
Set oFSO = CreateObject("Scripting.FileSystemObject")
sScriptDir = oFSO.GetParentFolderName(WScript.ScriptFullName)
sWatcher = sScriptDir & "\dispatch-watcher.ps1"

sCmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & sWatcher & """"

' Run(command, windowStyle, waitForCompletion)
'   windowStyle 0 = SW_HIDE
'   waitForCompletion False = fire-and-forget; wscript exits immediately
oShell.Run sCmd, 0, False
