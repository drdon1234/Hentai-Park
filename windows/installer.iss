; 安装及卸载仅管理程序文件；账号、书库与下载保留在原应用数据目录。
[Setup]
AppId={{79D96774-F741-4741-9920-775A83E394E0}
AppName=HentaiPark
AppVersion={#AppVersion}
AppPublisher=HentaiPark
AppPublisherURL=https://github.com/drdon1234/Hentai-Park
DefaultDirName={localappdata}\Programs\HentaiPark
DefaultGroupName=HentaiPark
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\hentai_park.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
LicenseFile=..\LICENSE

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\HentaiPark"; Filename: "{app}\hentai_park.exe"

[Run]
Filename: "{app}\hentai_park.exe"; Description: "Launch HentaiPark"; Flags: nowait postinstall skipifsilent
