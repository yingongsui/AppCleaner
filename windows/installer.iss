#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#ifndef OutputFileName
  #define OutputFileName "AppCleaner-windows-x64-setup"
#endif

[Setup]
AppId={{8E94A2F0-73C9-4536-A1E7-4B8021F5E9D1}
AppName=AppCleaner
AppVersion={#MyAppVersion}
AppPublisher=AppCleaner Contributors
DefaultDirName={autopf}\AppCleaner
DefaultGroupName=AppCleaner
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\build\installer
OutputBaseFilename={#OutputFileName}
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\app_cleaner.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\app_cleaner.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AppCleaner"; Filename: "{app}\app_cleaner.exe"
Name: "{autodesktop}\AppCleaner"; Filename: "{app}\app_cleaner.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\app_cleaner.exe"; Description: "{cm:LaunchProgram,AppCleaner}"; Flags: nowait postinstall skipifsilent
