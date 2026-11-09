; 明策终端 Windows 安装包 (Inno Setup 6)
; 构建: 先 flutter build windows --release, 再
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" desktop\installer\mingce.iss
; 产物: desktop\build\installer\mingce-win-setup.exe
;
; 免环境说明: Flutter Release 目录已 app-local 携带全部依赖
; (flutter_windows.dll / msvcp140.dll / vcruntime140*.dll), 用户机器无需
; 安装 Flutter / VC++ 运行库; 安装到 %LocalAppData%\Programs 免管理员权限.

#define MyAppName "明策终端"
#define MyAppVersion "1.0.0"
#define MyAppExe "noahs_ark_desktop.exe"

[Setup]
; 固定 AppId, 升级安装时识别旧版本覆盖
AppId={{7C4E9A2D-5B1F-4E38-9C6A-2D8F0B3E5A71}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=MINGCE
AppVerName={#MyAppName} {#MyAppVersion}
DefaultDirName={localappdata}\Programs\MingCeTerminal
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=mingce-win-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=110
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExe}
; 安装/卸载前自动关闭运行中的旧进程
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Languages]
Name: "chs"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "启动 {#MyAppName}"; \
  Flags: nowait postinstall skipifsilent
