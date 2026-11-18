; HentaiPark Windows User-Mode Installer (Inno Setup 6)
; All paths and version metadata are injected via ISCC /D defines; no machine-local paths.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef AppArch
  #define AppArch "x64"
#endif
#ifndef SourceDir
  #error "SourceDir must be provided via /DSourceDir=..."
#endif
#ifndef OutputDir
  #error "OutputDir must be provided via /DOutputDir=..."
#endif
#ifndef OutputBaseFilename
  #error "OutputBaseFilename must be provided via /DOutputBaseFilename=..."
#endif

[Setup]
AppId={{8E74A2B1-5C19-4F3A-9D82-6B01E4C92710}
AppName=HentaiPark
AppVersion={#AppVersion}
AppVerName=HentaiPark v{#AppVersion}
AppPublisher=HentaiPark Contributors
AppPublisherURL=https://github.com/drdon1234/Hentai-Park
AppSupportURL=https://github.com/drdon1234/Hentai-Park/issues
DefaultDirName={autopf}\HentaiPark
DefaultGroupName=HentaiPark
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
LicenseFile={#SourceDir}\assets\LICENSE
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
UninstallDisplayIcon={app}\HentaiPark.exe
#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\HentaiPark"; Filename: "{app}\HentaiPark.exe"
Name: "{autodesktop}\HentaiPark"; Filename: "{app}\HentaiPark.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\HentaiPark.exe"; Description: "{cm:LaunchProgram,HentaiPark}"; Flags: nowait postinstall skipifsilent
