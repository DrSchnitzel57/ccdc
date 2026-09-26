# AGENT: lapis (Windows Server 2016), 172.16.1.11 / public 192.168.200+x.11

**First read and obey `AGENT-RULES.md`.** Probably the **Domain Controller** (AD/DNS scored via LDAP login + DNS queries). May also run IIS (HTTP), FTP (IIS FTP/FileZilla), or RDP/SSH. Confirm in step 1. Use **PowerShell as Administrator**. Don't touch the `SplunkForwarder` service.

## Phase 1: harden (in this order)

### 1. Recon (read-only)
```powershell
hostname; ipconfig /all
Get-WindowsFeature | ? Installed | select Name
netstat -ano | findstr LISTEN
Get-Service | ? Status -eq Running | sort Name | ft Name,DisplayName
Get-ADDomain | select DNSRoot,NetBIOSName        # if a DC
Get-ADUser -Filter * -Properties MemberOf,Enabled,LastLogonDate | select Name,Enabled,LastLogonDate
"Domain Admins","Enterprise Admins","Schema Admins","Administrators","Remote Desktop Users","DnsAdmins","Group Policy Creator Owners" | % { "== $_"; Get-ADGroupMember $_ -Recursive | select -Expand SamAccountName }
Get-LocalUser    # on a DC this errors or shows little, which is normal
query user
```
Report: which scored services run here (port/process), accounts not on the allowed list, and who is in admin groups beyond steve/alex/Administrator.

### 2. Backup
```powershell
mkdir C:\bk -Force
secedit /export /cfg C:\bk\secpol.cfg
Backup-GPO -All -Path C:\bk    # needs GroupPolicy module (DC)
robocopy C:\inetpub C:\bk\inetpub /MIR    # if IIS
Get-ADUser -Filter * | Export-Csv C:\bk\users.csv
dnscmd /enumzones > C:\bk\dnszones.txt
```

### 3. Passwords (ask the human for new passwords)
```powershell
$pw = Read-Host -AsSecureString "Scored users new pw"
"steve","alex","enderman","creeper","villager","zombie","enderdragon","irongolem","chickenjockey","ghast" | % { Set-ADAccountPassword $_ -Reset -NewPassword $pw }
$apw = Read-Host -AsSecureString "Administrator pw"; Set-ADAccountPassword Administrator -Reset -NewPassword $apw
```
→ **Remind the human: PCR in Quotient.** Also check that no scored user has "must change password at next logon" set (it breaks scoring): `Set-ADUser <u> -ChangePasswordAtLogon $false`.
Optional later: reset `krbtgt` password once (it stops forged golden tickets). Ask the human first.

### 4. Users and groups
- Disable (don't delete) unknown accounts: `Disable-ADAccount <u>`.
- Remove unauthorized members from Domain Admins, Enterprise Admins, Schema Admins, Administrators, DnsAdmins, and Backup Operators: `Remove-ADGroupMember "<grp>" -Members <u> -Confirm:$false`.
- Disable Guest: `Disable-ADAccount Guest`.
- Find risky flags:
  ```powershell
  Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true}   # AS-REP roast → Set-ADAccountControl <u> -DoesNotRequirePreAuth $false
  Get-ADUser -Filter {ServicePrincipalName -like "*"} -Properties ServicePrincipalName  # kerberoastable
  Get-ADUser -Filter {PasswordNotRequired -eq $true}
  ```

### 5. Close the big Windows holes (safe on a 2016 DC)
```powershell
# SMBv1 off (EternalBlue)
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
# Print Spooler off (PrintNightmare) unless printing is needed
Stop-Service Spooler -Force; Set-Service Spooler -StartupType Disabled
# Zerologon enforcement
reg add HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters /v FullSecureChannelProtection /t REG_DWORD /d 1 /f
# WDigest off (no cleartext creds in memory)
reg add HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest /v UseLogonCredential /t REG_DWORD /d 0 /f
# LSA protection (takes effect after reboot, so only if a reboot is approved)
reg add HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v RunAsPPL /t REG_DWORD /d 1 /f
# Remote Registry off
Stop-Service RemoteRegistry -Force; Set-Service RemoteRegistry -StartupType Disabled
# RDP: require NLA (keep RDP on if scored or needed)
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
# Defender on
Set-MpPreference -DisableRealtimeMonitoring $false -DisableIOAVProtection $false
Get-MpPreference | select Exclusion*       # red team loves adding exclusions, so remove them:
# Remove-MpPreference -ExclusionPath "<path>"
```
Don't touch SMB signing, NTLM settings, or LDAP signing without testing, because they can break scoring logins.

### 6. Firewall, by port only
```powershell
Get-NetFirewallProfile | select Name,Enabled,DefaultInboundAction
Get-NetFirewallRule -Enabled True -Direction Inbound -Action Block | select DisplayName   # red-team blocks?
Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow | select DisplayName,@{n='Port';e={($_|Get-NetFirewallPortFilter).LocalPort}}
```
Make sure allow rules exist for what's scored, then enable:
```powershell
$ports = 53,88,135,389,445,464,636,3268,3269,80,443,21,3389   # trim/add per recon; 49152-65535 RPC dynamic is needed by AD
New-NetFirewallRule -DisplayName "CCDC-Allow-TCP" -Direction Inbound -Protocol TCP -LocalPort $ports -Action Allow
New-NetFirewallRule -DisplayName "CCDC-Allow-UDP" -Direction Inbound -Protocol UDP -LocalPort 53,88,123,389,464 -Action Allow
New-NetFirewallRule -DisplayName "CCDC-RPC-Dyn" -Direction Inbound -Protocol TCP -LocalPort 49152-65535 -Action Allow
Set-NetFirewallProfile -All -Enabled True
```
Then verify: `nslookup <domain> 127.0.0.1`, `Test-NetConnection 127.0.0.1 -Port 389`, and browse the site.

### 7. Persistence sweep
```powershell
Get-ScheduledTask | ? {$_.TaskPath -notlike "\Microsoft\*"} | select TaskName,TaskPath,State,@{n='Action';e={$_.Actions.Execute + " " + $_.Actions.Arguments}}
Get-CimInstance Win32_Service | ? {$_.PathName -notmatch "system32|Program Files"} | select Name,State,PathName
"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" | % { "== $_"; Get-ItemProperty $_ -EA 0 }
dir "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp","C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" -EA 0
Get-WmiObject -Namespace root\subscription -Class __EventConsumer        # WMI persistence
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\*" -EA 0 | ? Debugger   # sethc/utilman backdoors
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" | select Shell,Userinit
Get-ChildItem C:\Windows\Temp,C:\Users\Public,C:\ProgramData -Recurse -Include *.exe,*.ps1,*.bat,*.dll -EA 0 | ? LastWriteTime -gt (Get-Date).AddDays(-2)
dir C:\inetpub\wwwroot -Recurse -Include *.aspx,*.asp,*.php | ? LastWriteTime -gt (Get-Date).AddDays(-2)   # web shells
Get-NetTCPConnection -State Established | select LocalPort,RemoteAddress,RemotePort,OwningProcess,@{n='Proc';e={(Get-Process -Id $_.OwningProcess).Name}}
```
Also check that `sethc.exe` and `utilman.exe` in System32 are the real binaries (sticky-keys backdoor).

### 8. Logging
```powershell
auditpol /set /category:"Logon/Logoff","Account Logon","Account Management","Policy Change","Privilege Use","Detailed Tracking" /success:enable /failure:enable
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f
reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging /v EnableScriptBlockLogging /t REG_DWORD /d 1 /f
wevtutil sl Security /ms:524288000
```
Sysmon (if download works): get Sysmon from live.sysinternals.com, then `Sysmon64.exe -accepteula -i` (SwiftOnSecurity config if available).

### 9. Password/lockout policy (a common inject)
GPMC → Default Domain Policy → Computer Config → Policies → Windows Settings → Security Settings → Account Policies. Or: `Set-ADDefaultDomainPasswordPolicy -Identity <domain> -MinPasswordLength 12 -ComplexityEnabled $true -LockoutThreshold 5 -LockoutDuration 00:02:00 -LockoutObservationWindow 00:02:00`. **Warning:** a low lockout threshold lets red team lock out scored users. Keep it lenient (for example 10).

## Phase 2: hunt loop (every ~20 min)
New users/group changes (4720, 4728, 4732, 4756) → failed/successful logons (4625, 4624, type 3/10) → new services (7045) and tasks (4698) → `query user` → established connections → scheduled tasks → firewall rules → Defender detections (`Get-MpThreatDetection`) → scored service checks.
```powershell
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4720,4728,4732,4756,4698,1102;StartTime=(Get-Date).AddHours(-1)} | ft TimeCreated,Id,Message -Wrap
Get-WinEvent -FilterHashtable @{LogName='System';Id=7045;StartTime=(Get-Date).AddHours(-1)} | ft TimeCreated,Message -Wrap
```

## Scenarios
| Symptom | Do this |
|---|---|
| AD/LDAP login fails | `Get-Service NTDS,KDC,Netlogon,DNS` → start any stopped → account disabled/locked? (`Unlock-ADAccount`, `Enable-ADAccount`) → pw changed without PCR? → firewall 389/88 |
| DNS fails | `Get-Service DNS` → `Restart-Service DNS` → `Get-DnsServerZone` → check records weren't deleted (compare to `C:\bk\dnszones.txt`) → firewall UDP/TCP 53 |
| IIS down | `iisreset` → `Get-Website`, `Get-WebAppPoolState` → start the app pool → site bindings → content vs backup |
| FTP down | `Get-Service ftpsvc` → IIS FTP site started? → auth settings, firewall 21 and passive range |
| RDP down | `Get-Service TermService` → `fDenyTSConnections` = 0 → firewall 3389 → user in Remote Desktop Users |
| Malware / beacon | Record process, path, cmdline, hash (`Get-FileHash`), parent, and network connection. Screenshot, kill it, remove the file and persistence, run a Defender scan, log it |
| New admin user | Disable, remove from the group, check 4720/4732 for the creator account and source, log it |
| Firewall disabled by red team | Re-enable it, look for rogue rules/GPO (`gpresult /r`), log it |
