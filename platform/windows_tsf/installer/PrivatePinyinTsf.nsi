!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

!ifndef PRODUCT_VERSION
!define PRODUCT_VERSION "0.1.10"
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
RequestExecutionLevel user
Name "PrivatePinyin IME"
OutFile "${OUTPUT_PATH}"
Icon "${ICON_PATH}"
UninstallIcon "${ICON_PATH}"
InstallDir "$LOCALAPPDATA\PrivatePinyin"
InstallDirRegKey HKCU "Software\PrivatePinyin\Installer" "InstallDir"
SetCompressor /SOLID lzma
ManifestDPIAware true

VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName" "PrivatePinyin IME"
VIAddVersionKey "CompanyName" "PrivatePinyin"
VIAddVersionKey "FileDescription" "PrivatePinyin IME Setup"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "LegalCopyright" "All rights reserved."

!define MUI_ABORTWARNING
!define MUI_ICON "${ICON_PATH}"
!define MUI_UNICON "${ICON_PATH}"
!define MUI_FINISHPAGE_RUN "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
!define MUI_FINISHPAGE_RUN_PARAMETERS "-NoProfile -ExecutionPolicy Bypass -File $\"$INSTDIR\open-onboarding.ps1$\""
!define MUI_FINISHPAGE_RUN_TEXT "Open setup guide"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "PrivatePinyin IME currently ships as a 64-bit Windows input method. This installer requires 64-bit Windows."
    Abort
  ${EndIf}
  SetShellVarContext current
  SetRegView 64
FunctionEnd

Section "PrivatePinyin IME" SecMain
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
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayName" "PrivatePinyin IME"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "Publisher" "PrivatePinyin"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "DisplayIcon" "$INSTDIR\PrivatePinyinInstaller.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PrivatePinyin" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\PrivatePinyin IME"
  CreateShortcut "$SMPROGRAMS\PrivatePinyin IME\Setup Guide.lnk" "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File $\"$INSTDIR\open-onboarding.ps1$\"" "$INSTDIR\PrivatePinyinInstaller.ico"
  CreateShortcut "$SMPROGRAMS\PrivatePinyin IME\Preferences.lnk" "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File $\"$INSTDIR\open-settings.ps1$\"" "$INSTDIR\PrivatePinyinInstaller.ico"
  CreateShortcut "$SMPROGRAMS\PrivatePinyin IME\Uninstall.lnk" "$INSTDIR\uninstall.exe"

  ${DisableX64FSRedirection}
  ExecWait '"$WINDIR\System32\regsvr32.exe" /s "$INSTDIR\PrivatePinyinTsf.dll"' $0
  ${EnableX64FSRedirection}
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "PrivatePinyin IME was copied, but Windows TSF registration failed with exit code $0. Try reinstalling from a normal user account on 64-bit Windows."
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
