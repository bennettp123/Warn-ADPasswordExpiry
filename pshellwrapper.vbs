' Argument from command-line 
strFile = WScript.Arguments(0) 

Dim objShell, objFSO, objFile 

'WScript.Echo(WScript.Arguments.Count)
'WScript.Echo(WScript.Arguments(0))
'WScript.Echo(WScript.Arguments(1))
'WScript.Echo(WScript.Arguments(2))

Set objShell = CreateObject("WScript.Shell") 
Set objFSO = CreateObject("Scripting.FileSystemObject") 

If objFSO.FileExists(strFile) Then ' Check to see if the file exists 
 Set objFile = objFSO.GetFile(strFile) 
 strCmd = "powershell -nologo -command " & Chr(34) & "&{" & objFile.ShortPath
 If WScript.Arguments.Count > 1 Then
  For i = 1 To (WScript.Arguments.Count - 1)
   strCmd = strCmd & " " & WScript.Arguments(i)
  Next
 End If
 strCmd = strCmd & "}" & Chr(34) ' Chr(34) is ""
 objShell.Run strCmd, 0 '0 hides the window
Else
 WScript.Quit
End If