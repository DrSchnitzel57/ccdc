# Read-only baseline snapshot. Changes NOTHING on the system except writing C:\baseline-HHMM\
# Usage (Admin PowerShell):  Set-ExecutionPolicy -Scope Process Bypass -Force; .\windows-baseline.ps1
# Re-run later and compare:  Compare-Object (gc C:\baseline-0905\tasks.txt) (gc C:\baseline-1130\tasks.txt)
$T = Get-Date -Format HHmm; $D = "C:\baseline-$T"; New-Item -ItemType Directory $D -Force | Out-Null
$allowed = "steve","alex","enderman","creeper","villager","zombie","enderdragon","irongolem","chickenjockey","ghast","Administrator","Guest","krbtgt","DefaultAccount"
try { Get-ADUser -Filter * -Properties Enabled,whenCreated | select SamAccountName,Enabled,whenCreated | Out-File "$D\adusers.txt"
      "Domain Admins","Enterprise Admins","Schema Admins","Administrators","DnsAdmins","Remote Desktop Users" | % { "== $_"; Get-ADGroupMember $_ -Recursive -EA 0 | select -Expand SamAccountName } | Out-File "$D\admin-groups.txt"
      $extra = Get-ADUser -Filter * | ? { $allowed -notcontains $_.SamAccountName } | select -Expand SamAccountName
} catch { Get-LocalUser | Out-File "$D\localusers.txt"; $extra = Get-LocalUser | ? { $allowed -notcontains $_.Name } | select -Expand Name }
netstat -ano | Out-File "$D\netstat.txt"
Get-Process | select Id,ProcessName,Path | Out-File "$D\processes.txt" -Width 300
Get-CimInstance Win32_Service | select Name,State,StartMode,StartName,PathName | Out-File "$D\services.txt" -Width 400
Get-ScheduledTask | select TaskPath,TaskName,State,@{n='Exec';e={$_.Actions.Execute + ' ' + $_.Actions.Arguments}} | Out-File "$D\tasks.txt" -Width 400
"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" | % { "== $_"; Get-ItemProperty $_ -EA 0 | Out-String } | Out-File "$D\runkeys.txt"
Get-NetFirewallProfile | select Name,Enabled,DefaultInboundAction | Out-File "$D\fw-profiles.txt"
Get-NetFirewallRule -Enabled True | select DisplayName,Direction,Action | Out-File "$D\fw-rules.txt" -Width 300
Get-MpPreference | select DisableRealtimeMonitoring,Exclusion* | Out-File "$D\defender.txt" -Width 300
secedit /export /cfg "$D\secpol.cfg" | Out-Null
if (Test-Path C:\inetpub) { robocopy C:\inetpub "$D\inetpub" /MIR /NFL /NDL /NJH /NJS | Out-Null }
try { dnscmd /enumzones | Out-File "$D\dnszones.txt" } catch {}
Write-Host "[+] Baseline saved to $D"
Write-Host "[!] Accounts NOT on the allowed list:"; $extra
