Unicode true
!include "MUI2.nsh"

!define APPNAME "Green VPN"
Name "${APPNAME}"
OutFile "D:\greenvpn\desktop\dist\Green VPN Setup.exe"
InstallDir "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey HKLM "Software\${APPNAME}" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!define MUI_ICON "D:\greenvpn\desktop\ui\icon.ico"
!define MUI_UNICON "D:\greenvpn\desktop\ui\icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\Green VPN.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch Green VPN"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  File "D:\greenvpn\desktop\dist\Green VPN.exe"
  WriteRegStr HKLM "Software\${APPNAME}" "InstallDir" "$INSTDIR"
  ; Desktop + Start menu shortcuts (launch the exe -> its own UAC prompt for the VPN)
  CreateShortcut "$DESKTOP\Green VPN.lnk" "$INSTDIR\Green VPN.exe" "" "$INSTDIR\Green VPN.exe" 0
  CreateDirectory "$SMPROGRAMS\Green VPN"
  CreateShortcut "$SMPROGRAMS\Green VPN\Green VPN.lnk" "$INSTDIR\Green VPN.exe" "" "$INSTDIR\Green VPN.exe" 0
  CreateShortcut "$SMPROGRAMS\Green VPN\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  ; Add/Remove Programs entry
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN" "DisplayName" "Green VPN"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN" "DisplayIcon" "$INSTDIR\Green VPN.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN" "Publisher" "Green VPN"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN" "DisplayVersion" "2.0.8"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\Green VPN.exe"
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$DESKTOP\Green VPN.lnk"
  RMDir /r "$SMPROGRAMS\Green VPN"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN"
  DeleteRegKey HKLM "Software\Green VPN"
SectionEnd
