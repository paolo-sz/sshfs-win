!include LogicLib.nsh

; Upgrade codes (GUIDs)
!define UpgradeCode64 "{3576E993-BFE0-4707-B6F6-7F26BF88300B}"
!define UpgradeCode32 "{DC1B144B-4B64-4245-BC57-959267714315}"

;--------------------------------
; General Attributes

!define DisplayName "${MyProductName} ${MyProductVersion} (${MyArch})"

!if ${MyArch} == "x64"
  !define OtherUpgradeCode ${UpgradeCode32}
  !define UpgradeCode      ${UpgradeCode64}

  InstallDir "$PROGRAMFILES64\${MyProductName}"
!else
  !define OtherUpgradeCode ${UpgradeCode64}
  !define UpgradeCode      ${UpgradeCode32}

  InstallDir "$PROGRAMFILES\${MyProductName}"
!endif

Name "${DisplayName}"
OutFile "${MyOutFile}"
RequestExecutionLevel admin
ShowInstDetails show

;--------------------------------
; Pages

!define MUI_FINISHPAGE_NOAUTOCLOSE

!include "MUI2.nsh"

; Skip license page as in WiX (license is installed but no dialog)
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

;--------------------------------
; Languages
!insertmacro MUI_LANGUAGE "English"

;--------------------------------
; Variables

Var LauncherRegistryKey

;--------------------------------
; Functions

Function CheckOtherArchInstalled
  ; Check if other architecture version is installed by searching registry for UpgradeCode
  ClearErrors
  ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${OtherUpgradeCode}" "DisplayName"
  IfErrors done 0
    MessageBox MB_OK "A version of ${MyProductName} with a different computer architecture is already installed. You must uninstall it before you can install this version."
    Quit
done:
FunctionEnd

Function CheckUpgrade
  ; Check if older or newer version is installed and block accordingly
  ; This is a simplified check; real MSI upgrade logic is complex
  ; Here, we just check if product is installed by UpgradeCode and block install
  ClearErrors
  ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UpgradeCode}" "DisplayVersion"
  IfErrors 0 +2
    StrCpy $0 ""
  ; Compare versions (simple string compare, can be improved)
  StrCmp $0 "" done
  ; If installed version is same or newer, block install
  ; For simplicity, block if any version found
  MessageBox MB_OK "A version of ${MyProductName} is already installed. You must uninstall it before you can install this version."
  Quit
done:
FunctionEnd

;--------------------------------
; Installer Sections

Section "MainSection" SEC01
  ${If} ${MyArch} == "x64"
    SetRegView 64
  ${Else}
    SetRegView 32
  ${Endif}


  ; Check for other architecture installed
  Call CheckOtherArchInstalled

  ; Check for upgrade conflicts
  Call CheckUpgrade

  ; Create install directory
  CreateDirectory "$INSTDIR"

  ; Install License.txt
  SetOutPath "$INSTDIR"
  File "License.txt"

  ; Install all files and folders recursively from 'MySrcDir'
  File /r "${MySrcDir}\*"
  
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Write INSTDIR to registry
  WriteRegStr HKLM "Software\${MyProductName}" "InstallDir" "$INSTDIR"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UpgradeCode}" \
                 "DisplayName" "${DisplayName}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UpgradeCode}" \
                 "DisplayVersion" "${MyProductVersion}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UpgradeCode}" \
                 "Publisher" "${MyCompanyName}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UpgradeCode}" \
                 "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UpgradeCode}" \
                 "InstallLocation" "$INSTDIR"

  SetRegView 32

  StrCpy $LauncherRegistryKey "Software\WinFsp\Services"

  ; Write registry keys for sshfs services
  ; sshfs
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs" "Executable" "$INSTDIR\bin\sshfs-win.exe"
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs" "CommandLine" "svc %1 %2 -user %U -home %P -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o idmap=user -o max_readahead=1GB -o large_read -o kernel_cache -o follow_symlinks -o create_dir_umask=007 -o create_file_umask=117 -o reconnect -o max_conns=1" 
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs" "Security" "D:P(A;;RPWPLC;;;WD)"
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs" "JobControl" 1
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs" "Credentials" 1

  ; sshfs.r
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.r" "Executable" "$INSTDIR\bin\sshfs-win.exe"
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.r" "CommandLine" "svc %1 %2 -user %U -home %P -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o idmap=user -o max_readahead=1GB -o large_read -o kernel_cache -o follow_symlinks -o create_dir_umask=007 -o create_file_umask=117 -o reconnect -o max_conns=1"
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.r" "Security" "D:P(A;;RPWPLC;;;WD)"
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs.r" "JobControl" 1
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs.r" "Credentials" 1
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs.r" "sshfs.rootdir" 1

  ; sshfs.k
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.k" "Executable" "$INSTDIR\bin\sshfs-win.exe"
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.k" "CommandLine" "svc %1 %2 -user %U -home %P -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o idmap=user -o max_readahead=1GB -o large_read -o kernel_cache -o follow_symlinks -o create_dir_umask=007 -o create_file_umask=117 -o reconnect -o max_conns=1"
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.k" "Security" "D:P(A;;RPWPLC;;;WD)"
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs.k" "JobControl" 1
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs.k" "Credentials" 0

  ; sshfs.kr
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.kr" "Executable" "$INSTDIR\bin\sshfs-win.exe"
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.kr" "CommandLine" "svc %1 %2 -user %U -home %P -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o idmap=user -o max_readahead=1GB -o large_read -o kernel_cache -o follow_symlinks -o create_dir_umask=007 -o create_file_umask=117 -o reconnect -o max_conns=1"
  WriteRegStr HKLM "$LauncherRegistryKey\sshfs.kr" "Security" "D:P(A;;RPWPLC;;;WD)"
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs.kr" "JobControl" 1
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs.kr" "Credentials" 0
  WriteRegDWORD HKLM "$LauncherRegistryKey\sshfs.kr" "sshfs.rootdir" 1
  
SectionEnd

;--------------------------------
; Uninstaller

Section "Uninstall"
  ${If} ${MyArch} == "x64"
    SetRegView 64
  ${Else}
    SetRegView 32
  ${Endif}

  ; Remove all files and folders installed recursively
  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UpgradeCode}"
  DeleteRegKey HKLM "Software\${MyProductName}"

  SetRegView 32

  StrCpy $LauncherRegistryKey "Software\WinFsp\Services"

  ; Remove registry keys
  DeleteRegKey HKLM "$LauncherRegistryKey\sshfs"
  DeleteRegKey HKLM "$LauncherRegistryKey\sshfs.r"
  DeleteRegKey HKLM "$LauncherRegistryKey\sshfs.k"
  DeleteRegKey HKLM "$LauncherRegistryKey\sshfs.kr"

SectionEnd