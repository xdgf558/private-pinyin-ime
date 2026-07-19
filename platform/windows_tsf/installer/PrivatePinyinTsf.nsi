!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

!ifndef PRODUCT_VERSION
!define PRODUCT_VERSION "0.1.23"
!endif

!define APP_DIR_NAME "app-${PRODUCT_VERSION}"

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
  Exec '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "$INSTDIR\${APP_DIR_NAME}\open-onboarding.ps1"'
  onboarding_done:
FunctionEnd

Section "猫栈拼音" SecMain
  SetShellVarContext current
  SetRegView 64
  SetOutPath "$INSTDIR\${APP_DIR_NAME}\x64"
  File "${PACKAGE_SOURCE}\x64\PrivatePinyinTsf.dll"
  File "${PACKAGE_SOURCE}\x64\private_pinyin_ime.dll"
  File "${PACKAGE_SOURCE}\x64\PrivatePinyinInstaller.ico"

  SetOutPath "$INSTDIR\${APP_DIR_NAME}\x86"
  File "${PACKAGE_SOURCE}\x86\PrivatePinyinTsf.dll"
  File "${PACKAGE_SOURCE}\x86\private_pinyin_ime.dll"
  File "${PACKAGE_SOURCE}\x86\PrivatePinyinInstaller.ico"

  SetOutPath "$INSTDIR\${APP_DIR_NAME}"
  File "${PACKAGE_SOURCE}\private-pinyin-settings.exe"
  File "${PACKAGE_SOURCE}\register-ime.ps1"
  File "${PACKAGE_SOURCE}\unregister-ime.ps1"
  File "${PACKAGE_SOURCE}\open-settings.ps1"
  File "${PACKAGE_SOURCE}\open-onboarding.ps1"
  File "${PACKAGE_SOURCE}\ReleaseNotes.zh-Hans.txt"
  File "${PACKAGE_SOURCE}\PrivatePinyinInstaller.ico"
  File "${PACKAGE_SOURCE}\PrivatePinyinLogo.png"
  File "${PACKAGE_SOURCE}\default_settings.json"
  File "${PACKAGE_SOURCE}\version.txt"

  WriteRegStr HKCU "Software\PrivatePinyin\Installer" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayName" "猫栈拼音"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "Publisher" "猫栈"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayIcon" "$INSTDIR\${APP_DIR_NAME}\PrivatePinyinInstaller.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "NoRepair" 1

  Delete "$SMPROGRAMS\PrivatePinyin IME\Setup Guide.lnk"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Preferences.lnk"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Uninstall.lnk"
  RMDir "$SMPROGRAMS\PrivatePinyin IME"

  CreateDirectory "$SMPROGRAMS\猫栈拼音"
  CreateShortcut "$SMPROGRAMS\猫栈拼音\安装引导.lnk" "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File $\"$INSTDIR\${APP_DIR_NAME}\open-onboarding.ps1$\"" "$INSTDIR\${APP_DIR_NAME}\PrivatePinyinInstaller.ico"
  CreateShortcut "$SMPROGRAMS\猫栈拼音\偏好设置.lnk" "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File $\"$INSTDIR\${APP_DIR_NAME}\open-settings.ps1$\"" "$INSTDIR\${APP_DIR_NAME}\PrivatePinyinInstaller.ico"
  CreateShortcut "$SMPROGRAMS\猫栈拼音\更新说明.lnk" "$WINDIR\System32\notepad.exe" "$\"$INSTDIR\${APP_DIR_NAME}\ReleaseNotes.zh-Hans.txt$\"" "$INSTDIR\${APP_DIR_NAME}\PrivatePinyinInstaller.ico"
  CreateShortcut "$SMPROGRAMS\猫栈拼音\卸载.lnk" "$INSTDIR\uninstall.exe"

  ${DisableX64FSRedirection}
  ExecWait '"$WINDIR\System32\regsvr32.exe" /u /s "$INSTDIR\${APP_DIR_NAME}\x64\PrivatePinyinTsf.dll"'
  ExecWait '"$WINDIR\System32\regsvr32.exe" /s "$INSTDIR\${APP_DIR_NAME}\x64\PrivatePinyinTsf.dll"' $0
  ${EnableX64FSRedirection}
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "猫栈拼音文件已复制，但 64 位 Windows TSF 注册失败，regsvr32 退出码为 $0。请关闭正在使用旧输入法的应用，然后重新运行安装器。"
    Abort
  ${EndIf}

  ExecWait '"$WINDIR\SysWOW64\regsvr32.exe" /u /s "$INSTDIR\${APP_DIR_NAME}\x86\PrivatePinyinTsf.dll"'
  ExecWait '"$WINDIR\SysWOW64\regsvr32.exe" /s "$INSTDIR\${APP_DIR_NAME}\x86\PrivatePinyinTsf.dll"' $1
  ${If} $1 != 0
    ${DisableX64FSRedirection}
    ExecWait '"$WINDIR\System32\regsvr32.exe" /u /s "$INSTDIR\${APP_DIR_NAME}\x64\PrivatePinyinTsf.dll"'
    ${EnableX64FSRedirection}
    MessageBox MB_ICONSTOP "猫栈拼音文件已复制，但 QQ 等 32 位应用所需的 TSF 组件注册失败，regsvr32 退出码为 $1。请关闭 QQ 后重新运行安装器。"
    Abort
  ${EndIf}

  ; Running applications may still hold an older TSF/FFI DLL. Keep the new
  ; version in its own directory and defer old file removal until Windows can.
  Delete /REBOOTOK "$INSTDIR\PrivatePinyinTsf.dll"
  Delete /REBOOTOK "$INSTDIR\private_pinyin_ime.dll"
  Delete /REBOOTOK "$INSTDIR\private-pinyin-settings.exe"
  Delete /REBOOTOK "$INSTDIR\register-ime.ps1"
  Delete /REBOOTOK "$INSTDIR\unregister-ime.ps1"
  Delete /REBOOTOK "$INSTDIR\open-settings.ps1"
  Delete /REBOOTOK "$INSTDIR\open-onboarding.ps1"
  Delete /REBOOTOK "$INSTDIR\ReleaseNotes.zh-Hans.txt"
  Delete /REBOOTOK "$INSTDIR\PrivatePinyinInstaller.ico"
  Delete /REBOOTOK "$INSTDIR\PrivatePinyinLogo.png"
  Delete /REBOOTOK "$INSTDIR\default_settings.json"
  Delete /REBOOTOK "$INSTDIR\version.txt"

  FindFirst $1 $2 "$INSTDIR\app-*"
  cleanup_old_versions:
    StrCmp $2 "" cleanup_old_versions_done
    StrCmp $2 "${APP_DIR_NAME}" cleanup_old_versions_next
    RMDir /r /REBOOTOK "$INSTDIR\$2"
  cleanup_old_versions_next:
    FindNext $1 $2
    Goto cleanup_old_versions
  cleanup_old_versions_done:
    FindClose $1

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  SetRegView 64

  ${DisableX64FSRedirection}
  ExecWait '"$WINDIR\System32\regsvr32.exe" /u /s "$INSTDIR\${APP_DIR_NAME}\x64\PrivatePinyinTsf.dll"'
  ${EnableX64FSRedirection}
  ExecWait '"$WINDIR\SysWOW64\regsvr32.exe" /u /s "$INSTDIR\${APP_DIR_NAME}\x86\PrivatePinyinTsf.dll"'

  Delete "$SMPROGRAMS\猫栈拼音\安装引导.lnk"
  Delete "$SMPROGRAMS\猫栈拼音\偏好设置.lnk"
  Delete "$SMPROGRAMS\猫栈拼音\更新说明.lnk"
  Delete "$SMPROGRAMS\猫栈拼音\卸载.lnk"
  RMDir "$SMPROGRAMS\猫栈拼音"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Setup Guide.lnk"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Preferences.lnk"
  Delete "$SMPROGRAMS\PrivatePinyin IME\Uninstall.lnk"
  RMDir "$SMPROGRAMS\PrivatePinyin IME"

  FindFirst $1 $2 "$INSTDIR\app-*"
  uninstall_versions:
    StrCmp $2 "" uninstall_versions_done
    RMDir /r /REBOOTOK "$INSTDIR\$2"
    FindNext $1 $2
    Goto uninstall_versions
  uninstall_versions_done:
    FindClose $1

  Delete /REBOOTOK "$INSTDIR\PrivatePinyinTsf.dll"
  Delete /REBOOTOK "$INSTDIR\private_pinyin_ime.dll"
  Delete /REBOOTOK "$INSTDIR\private-pinyin-settings.exe"
  Delete /REBOOTOK "$INSTDIR\register-ime.ps1"
  Delete /REBOOTOK "$INSTDIR\unregister-ime.ps1"
  Delete /REBOOTOK "$INSTDIR\open-settings.ps1"
  Delete /REBOOTOK "$INSTDIR\open-onboarding.ps1"
  Delete /REBOOTOK "$INSTDIR\ReleaseNotes.zh-Hans.txt"
  Delete /REBOOTOK "$INSTDIR\PrivatePinyinInstaller.ico"
  Delete /REBOOTOK "$INSTDIR\PrivatePinyinLogo.png"
  Delete /REBOOTOK "$INSTDIR\default_settings.json"
  Delete /REBOOTOK "$INSTDIR\version.txt"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin"
  DeleteRegKey HKCU "Software\PrivatePinyin\Installer"
SectionEnd
