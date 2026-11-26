; Installer of mpv-dlssg for Windows x86_64, run by build-installer.sh.
;
; PERSONAL USE ONLY. It packs GPL code (mpv, FFmpeg) linked with the
; proprietary NVIDIA NGX SDK, plus NVIDIA's own library.

Unicode true
SetCompressor /SOLID lzma

!define APP "mpv-dlssg"
!define WARNING "DO NOT DISTRIBUTE UNDER ANY CIRCUMSTANCES"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP}"
!define APP_KEY "Software\${APP}"

!include "MUI2.nsh"
!include "LogicLib.nsh"

Name "${APP}"
Caption "${APP} setup - ${WARNING}"
UninstallCaption "${APP} uninstall - ${WARNING}"
BrandingText "${WARNING}"
OutFile "${OUTFILE}"
; per user, so that no administrator rights are needed
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${APP_KEY}" "InstallDir"

VIProductVersion "0.0.0.0"
VIAddVersionKey "ProductName" "${APP} (${WARNING})"
VIAddVersionKey "FileDescription" "${APP} setup - ${WARNING}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Personal use only. ${WARNING}."

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "${WARNING}"
!define MUI_WELCOMEPAGE_TITLE_3LINES
!define MUI_WELCOMEPAGE_TEXT "This is ${APP} ${VERSION}: mpv with NVIDIA DLSS Frame Generation and the ModernZ interface.$\r$\n$\r$\n${WARNING}.$\r$\n$\r$\nIt is a package for personal use: do not copy it to other people, do not upload it anywhere and do not publish it."
!define MUI_LICENSEPAGE_TEXT_TOP "${WARNING}"
!define MUI_LICENSEPAGE_CHECKBOX
!define MUI_LICENSEPAGE_CHECKBOX_TEXT "I will not distribute it under any circumstances"
!define MUI_FINISHPAGE_RUN "$INSTDIR\mpv.exe"
!define MUI_FINISHPAGE_RUN_PARAMETERS "--player-operation-mode=pseudo-gui"
!define MUI_FINISHPAGE_RUN_TEXT "Start ${APP}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${NOTICE}"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

!macro shortcut link
  CreateShortcut "${link}" "$INSTDIR\mpv.exe" "--player-operation-mode=pseudo-gui" "$INSTDIR\mpv.exe" 0
!macroend

Section "${APP} (required)" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /r "${PROGRAM}\*"
  ; configuration the user may have changed is kept when installing again
  SetOverwrite off
  File /r "${CONFIG}\*"
  SetOverwrite on

  WriteRegStr HKCU "${APP_KEY}" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP} (${WARNING})"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\mpv.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  !insertmacro shortcut "$SMPROGRAMS\${APP}.lnk"
SectionEnd

Section "Desktop shortcut" SecDesktop
  SetOutPath "$INSTDIR"
  !insertmacro shortcut "$DESKTOP\${APP}.lnk"
SectionEnd

Section /o "Register as a video player (listed as mpv)" SecRegister
  ExecWait '"$INSTDIR\mpv.exe" --register'
  WriteRegDWORD HKCU "${APP_KEY}" "Registered" 1
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} "The player, DLSS Frame Generation, the interface and a Start menu entry."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "A shortcut on the desktop."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecRegister} "Offers it in 'Open with' and Default apps. Replaces the registration of another mpv, if you have one."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  ReadRegDWORD $0 HKCU "${APP_KEY}" "Registered"
  ${If} $0 = 1
    ExecWait '"$INSTDIR\mpv.exe" --unregister'
  ${EndIf}
  ; only what was installed is removed, never the whole directory
  !include "${DELETE_LIST}"
  RMDir /r "$INSTDIR\portable_config\cache"
  RMDir "$INSTDIR\portable_config"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "${APP_KEY}"
SectionEnd
