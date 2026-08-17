; Minecraft 統合版 アカウント切り替え - インストーラー定義
; 作者: Ragazzo249
;
; ビルドは build-installer.ps1 から行う。
; 管理者権限を必要としないユーザー単位インストールにしてある。

#define AppName "Minecraft アカウント切り替え"
#define AppVersion "1.1.0"
#define AppPublisher "Ragazzo249"
#define AppURL "https://github.com/Ragazzo249/mc-account-switcher"
#define PSExe "{sys}\WindowsPowerShell\v1.0\powershell.exe"
#define PSArgs "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """"{app}\mc-switcher.ps1"""""

[Setup]
AppId={{9C4B7A21-3E5D-4F8A-B6C1-2D7E8F0A1B3C}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases

; 管理者権限を求めない。インストール先はユーザーごとの Programs 配下になる。
; プロファイルをインストール先へ書き込むため、書き込み可能な場所に入れる必要がある
PrivilegesRequired=lowest
DefaultDirName={autopf}\MinecraftAccountSwitcher
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

; 64bit 環境では本物の System32 を {sys} で参照できるようにする
ArchitecturesInstallIn64BitMode=x64compatible

OutputDir=..\dist
OutputBaseFilename=mc-account-switcher-setup-{#AppVersion}
SetupIconFile=..\assets\app.ico
UninstallDisplayIcon={app}\app.ico
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\LICENSE

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\mc-switcher.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\mc-switcher.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\mc-profile.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\lib.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\snapshot.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\compare.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\app.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; .ps1 は直接起動できないため powershell.exe を叩き、アイコンだけ差し替える
Name: "{autoprograms}\{#AppName}"; Filename: "{#PSExe}"; Parameters: "{#PSArgs}"; WorkingDir: "{app}"; IconFilename: "{app}\app.ico"; Comment: "{#AppName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{#PSExe}"; Parameters: "{#PSArgs}"; WorkingDir: "{app}"; IconFilename: "{app}\app.ico"; Comment: "{#AppName}"; Tasks: desktopicon

[Run]
Filename: "{#PSExe}"; Parameters: "{#PSArgs}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; アカウント情報を残す選択をした場合はフォルダも残る。
; 空になっていれば削除して、フォルダを残さない
Type: dirifempty; Name: "{app}"

[Code]
// アンインストール時に、登録したアカウント情報を残すか消すかを確認する。
// メールアドレスを含むため、黙って残さない
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    AppDir := ExpandConstant('{app}');
    if DirExists(AppDir + '\profiles') or FileExists(AppDir + '\settings.json') then
    begin
      if MsgBox('登録したアカウント情報も削除しますか？' + #13#10 + #13#10 +
                'いいえを選ぶと残ります。再インストールすればそのまま使えます。' + #13#10 +
                '（メールアドレスが含まれるため、PC を手放す場合は削除してください）',
                mbConfirmation, MB_YESNO) = IDYES then
      begin
        DelTree(AppDir + '\profiles', True, True, True);
        DeleteFile(AppDir + '\settings.json');
      end;
    end;
  end;
end;
