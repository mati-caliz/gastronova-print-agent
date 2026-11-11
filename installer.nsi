; Gastronova Impresion — Instalador Windows
; Genera un .exe que instala el host de impresion.
; Build: makensis -DSTAGING=staging installer.nsi

SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "StrFunc.nsh"
${StrRep}

!ifndef STAGING
  !define STAGING "staging"
!endif

!ifndef VERSION
  !define VERSION "0.0.0"
!endif

; --- Metadata ----------------------------------------------------------------

Name "Gastronova Impresion"
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1034 "ProductName" "Gastronova Impresion"
VIAddVersionKey /LANG=1034 "CompanyName" "Gastronova"
VIAddVersionKey /LANG=1034 "FileDescription" "Instalador del componente de impresion de Gastronova"
VIAddVersionKey /LANG=1034 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1034 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1034 "LegalCopyright" "Gastronova - Licencia MIT"
OutFile "gastronova-impresion.exe"
InstallDir "$LOCALAPPDATA\GastroNova"
RequestExecutionLevel user
Unicode true

; --- UI ----------------------------------------------------------------------

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Spanish"

; --- Check previous installation ---------------------------------------------

Function .onInit
  ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GastronovaImpresion" \
    "UninstallString"
  StrCmp $0 "" done

  MessageBox MB_OKCANCEL|MB_ICONINFORMATION \
    "Gastronova Impresion ya esta instalado.$\n$\nSe desinstalara la version anterior antes de continuar." \
    /SD IDOK IDOK uninstall
  Abort

  uninstall:
    ExecWait '$0 /S _?=$INSTDIR'
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR"

  done:
FunctionEnd

; --- Install -----------------------------------------------------------------

Section "Install"
  SetOutPath "$INSTDIR"

  File "${STAGING}/gastronova-print-host.exe"

  ; Manifest JSON para Chrome Native Messaging
  ; Usa forward slashes que son validas en JSON y Windows las acepta
  ${StrRep} $1 "$INSTDIR\gastronova-print-host.exe" `\` `/`
  FileOpen $0 "$INSTDIR\com.gastronova.print_host.json" w
  FileWrite $0 `{$\r$\n`
  FileWrite $0 `  "name": "com.gastronova.print_host",$\r$\n`
  FileWrite $0 `  "description": "GastroNova - Host de impresion termica",$\r$\n`
  FileWrite $0 `  "path": "$1",$\r$\n`
  FileWrite $0 `  "type": "stdio",$\r$\n`
  FileWrite $0 `  "allowed_origins": [$\r$\n`
  FileWrite $0 `    "chrome-extension://hjhbknickakeacelnjfldbbhnobdibjc/"$\r$\n`
  FileWrite $0 `  ]$\r$\n`
  FileWrite $0 `}$\r$\n`
  FileClose $0

  ; Registry — Chrome Native Messaging Host
  WriteRegStr HKCU "Software\Google\Chrome\NativeMessagingHosts\com.gastronova.print_host" \
    "" "$INSTDIR\com.gastronova.print_host.json"

  ; Registry — Edge Native Messaging Host
  WriteRegStr HKCU "Software\Microsoft\Edge\NativeMessagingHosts\com.gastronova.print_host" \
    "" "$INSTDIR\com.gastronova.print_host.json"

  ; Uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Agregar o quitar programas
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GastronovaImpresion" \
    "DisplayName" "Gastronova Impresion"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GastronovaImpresion" \
    "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GastronovaImpresion" \
    "Publisher" "Gastronova"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GastronovaImpresion" \
    "DisplayVersion" "${VERSION}"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GastronovaImpresion" \
    "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GastronovaImpresion" \
    "NoRepair" 1
SectionEnd

; --- Uninstall ---------------------------------------------------------------

Section "Uninstall"
  DeleteRegKey HKCU "Software\Google\Chrome\NativeMessagingHosts\com.gastronova.print_host"
  DeleteRegKey HKCU "Software\Microsoft\Edge\NativeMessagingHosts\com.gastronova.print_host"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GastronovaImpresion"
  RMDir /r "$INSTDIR"
SectionEnd
