; Det App Windows installer
; Layout matches portable so in-app updates keep working:
;   {app}\app\det_app.exe
;   {app}\update\DetAppUpdate.ps1
;
; Build (from pack_release.ps1):
;   ISCC.exe /DMyAppVersion=1.0.1 /DMyAppBuild=112 /DSourceDir=...\dist\DetApp-portable tools\detapp_setup.iss

#ifndef MyAppVersion
  #define MyAppVersion "1.0.1"
#endif
#ifndef MyAppBuild
  #define MyAppBuild "0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\DetApp-portable"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define MyAppName "Det App"
#define MyAppPublisher "Det App"
#define MyAppURL "https://det-app.ru"
#define MyAppExeName "det_app.exe"

[Setup]
AppId={{8F3C2A91-6B4E-4D1A-9C7F-2E5A8B0D1F44}
AppName={#MyAppName}
AppVersion={#MyAppVersion}+{#MyAppBuild}
AppVerName={#MyAppName} {#MyAppVersion}+{#MyAppBuild}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\DetApp
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; User-writable path required: updater renames app\ → app.bak
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=DetApp-Setup-{#MyAppVersion}-b{#MyAppBuild}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\app\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
CloseApplications=force
RestartApplications=no
DirExistsWarning=no
UsedUserAreasWarning=no
InfoBeforeFile=
LicenseFile=
; Keep custom paths writable (avoid Program Files)
AllowNoIcons=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Full portable tree: app\, update\, docs, channel, optional vc_redist
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\app\{#MyAppExeName}"; WorkingDir: "{app}\app"; IconFilename: "{app}\app\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\app\{#MyAppExeName}"; WorkingDir: "{app}\app"; Tasks: desktopicon; IconFilename: "{app}\app\{#MyAppExeName}"

[Run]
; Optional VC++ — only if bundled; may prompt UAC
Filename: "{app}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Visual C++ Redistributable…"; Flags: waituntilterminated skipifdoesntexist; Check: VcRedistNeeded
Filename: "{app}\app\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}\app"

[UninstallDelete]
; After auto-updates, files may appear that Setup did not track
Type: filesandordirs; Name: "{app}\app"
Type: filesandordirs; Name: "{app}\app.bak"
Type: filesandordirs; Name: "{app}\update"
Type: files; Name: "{app}\update_channel.json"
Type: dirifempty; Name: "{app}"

[Code]
function VcRedistNeeded(): Boolean;
var
  Paths: array[0..2] of String;
  I: Integer;
begin
  // Skip if a recent VC runtime looks present
  Paths[0] := ExpandConstant('{sys}\vcruntime140.dll');
  Paths[1] := ExpandConstant('{sys}\msvcp140.dll');
  Paths[2] := ExpandConstant('{sys}\vcruntime140_1.dll');
  for I := 0 to 2 do
  begin
    if not FileExists(Paths[I]) then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  DirLower: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    DirLower := LowerCase(WizardDirValue);
    if (Pos('\program files', DirLower) > 0) or (Pos('\program files (x86)', DirLower) > 0) then
    begin
      MsgBox(
        'Нельзя ставить в Program Files.'#13#10#13#10 +
        'Автообновления требуют запись в папку приложения.'#13#10 +
        'Оставьте путь вида:'#13#10 +
        ExpandConstant('{localappdata}') + '\DetApp',
        mbError, MB_OK);
      Result := False;
    end;
  end;
end;
