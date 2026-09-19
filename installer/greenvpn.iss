; Green VPN — Windows installer (per-user, no admin required)
; Build:  ISCC.exe installer\greenvpn.iss   -> dist\Green VPN Setup.exe

#define MyAppName    "Green VPN"
#define MyAppVersion "7.6.2"
#define MyAppPublisher "Oscar"
#define MyAppExe     "Green VPN.exe"
#define MyAppURL     "https://green-vpn.app"

[Setup]
AppId={{A7F3C2E1-9B4D-4E6A-8C1F-2D5E7A9B3C4F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
; Per-user install => no UAC prompt, {autopf} => %LocalAppData%\Programs
PrivilegesRequired=lowest
OutputDir=D:\greenvpn\desktop\dist
OutputBaseFilename=Green VPN Setup
SetupIconFile=D:\greenvpn\desktop\ui\icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "D:\greenvpn\desktop\dist\Green VPN.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
; shellexec (not plain CreateProcess) so Windows honors Green VPN.exe's requireAdministrator
; manifest and pops the UAC prompt itself -- without it, the installer (which runs
; unelevated, PrivilegesRequired=lowest) fails with "CreateProcess failed; code 740:
; The requested operation requires elevation" when trying to auto-launch the app.
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent shellexec
