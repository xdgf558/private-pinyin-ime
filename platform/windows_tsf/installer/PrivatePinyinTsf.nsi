!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

!ifndef PRODUCT_VERSION
!define PRODUCT_VERSION "0.1.12"
!endif

!ifndef PACKAGE_SOURCE
!define PACKAGE_SOURCE "..\..\..\dist\windows_tsf\PrivatePinyin-${PRODUCT_VERSION}"
!endif

!ifndef OUTPUT_PATH
!define OUTPUT_PATH "..\..\..\dist\windows_tsf\PrivatePinyin-${PRODUCT_VERSION}-setup.exe"
!endif

!ifndef ICON_PATH
!define ICON_PATH "platform\windows_tsf\installer\PrivatePinyinInstaller.ico"
!endif

Unicode true
RequestExecutionLevel admin
Name "猫栈拼音"
OutFile "${OUTPUT_PATH}"
Icon "${ICON_PATH}"
UninstallIcon "${ICON_PATH}"
InstallDir "$LOCALAPPDATA\PrivatePinyin"
InstallDirRegKey HKCU "Software\PrivatePinyin\Installer" "InstallDir"
SetCompressor /SOLID lzma
ManifestDPIAware true

VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName" "猫栈拼音"
VIAddVersionKey "CompanyName" "猫栈"
VIAddVersionKey "FileDescription" "猫栈拼音安装程序"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "LegalCopyright" "All rights reserved."

!define MUI_ABORTWARNING
!define MUI_ICON "${ICON_PATH}"
!define MUI_UNICON "${ICON_PATH}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "猫栈拼音目前只提供 64 位 Windows 输入法。请在 64 位 Windows 上安装。"
    Abort
  ${EndIf}
  SetShellVarContext current
  SetRegView 64
FunctionEnd

Function .onInstSuccess
  IfSilent onboarding_done
  Exec '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\open-onboarding.ps1"'
  onboarding_done:
FunctionEnd

Section "猫栈拼音" SecMain
  SetShellVarContext current
  SetRegView 64
  SetOutPath "$INSTDIR"

  File "${PACKAGE_SOURCE}\PrivatePinyinTsf.dll"
  File "${PACKAGE_SOURCE}\private_pinyin_ime.dll"
  File "${PACKAGE_SOURCE}\private-pinyin-settings.exe"
  File "${PACKAGE_SOURCE}\register-ime.ps1"
  File "${PACKAGE_SOURCE}\unregister-ime.ps1"
  File "${PACKAGE_SOURCE}\open-settings.ps1"
  File "${PACKAGE_SOURCE}\open-onboarding.ps1"
  File "${PACKAGE_SOURCE}\PrivatePinyinInstaller.ico"
  File "${PACKAGE_SOURCE}\default_settings.json"

  WriteRegStr HKCU "Software\PrivatePinyin\Installer" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayName" "猫栈拼音"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "Publisher" "猫栈"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayIcon" "$INSTDIR\PrivatePinyinInstaller.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "NoRepair" 1

  Delete "$SMPROGRAMS\PrivatePinyin IME\Setup Guide.lnk"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Preferences.lnk"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Uninstall.lnk"
  RMDir "$SMPROGRAMS\PrivatePinyin IME"

  CreateDirectory "$SMPROGRAMS\猫栈拼音"
  CreateShortcut "$SMPROGRAMS\猫栈拼音\安装引导.lnk" "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File $\"$INSTDIR\open-onboarding.ps1$\"" "$INSTDIR\PrivatePinyinInstaller.ico"
  CreateShortcut "$SMPROGRAMS\猫栈拼音\偏好设置.lnk" "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File $\"$INSTDIR\open-settings.ps1$\"" "$INSTDIR\PrivatePinyinInstaller.ico"
  CreateShortcut "$SMPROGRAMS\猫栈拼音\卸载.lnk" "$INSTDIR\uninstall.exe"

  ${DisableX64FSRedirection}
  ExecWait '"$WINDIR\System32\regsvr32.exe" /u /s "$INSTDIR\PrivatePinyinTsf.dll"'
  ExecWait '"$WINDIR\System32\regsvr32.exe" /s "$INSTDIR\PrivatePinyinTsf.dll"' $0
  ${EnableX64FSRedirection}
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "猫栈拼音文件已复制，但 Windows TSF 注册失败，regsvr32 退出码为 $0。请关闭正在使用旧输入法的应用，然后在 64 位 Windows 上以管理员身份重新运行安装器。如果仍失败，请先卸载旧版本，注销并重新登录后再安装。"
    Abort
  ${EndIf}

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  SetRegView 64

  ${DisableX64FSRedirection}
  ExecWait '"$WINDIR\System32\regsvr32.exe" /u /s "$INSTDIR\PrivatePinyinTsf.dll"'
  ${EnableX64FSRedirection}

  Delete "$SMPROGRAMS\猫栈拼音\安装引导.lnk"
  Delete "$SMPROGRAMS\猫栈拼音\偏好设置.lnk"
  Delete "$SMPROGRAMS\猫栈拼音\卸载.lnk"
  RMDir "$SMPROGRAMS\猫栈拼音"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Setup Guide.lnk"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Preferences.lnk"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Uninstall.lnk"
  RMDir "$SMPROGRAMS\PrivatePinyin IME"

  Delete "$INSTDIR\PrivatePinyinTsf.dll"
  Delete "$INSTDIR\private_pinyin_ime.dll"
  Delete "$INSTDIR\private-pinyin-settings.exe"
  Delete "$INSTDIR\register-ime.ps1"
  Delete "$INSTDIR\unregister-ime.ps1"
  Delete "$INSTDIR\open-settings.ps1"
  Delete "$INSTDIR\open-onboarding.ps1"
  Delete "$INSTDIR\PrivatePinyinInstaller.ico"
  Delete "$INSTDIR\default_settings.json"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin"
  DeleteRegKey HKCU "Software\PrivatePinyin\Installer"
SectionEnd
