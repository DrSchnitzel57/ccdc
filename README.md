# BYU CCDC Tryouts 2026 – My Playbook (Mojank Studios)

> Public notes repo (allowed under Rule 7). **Nothing in here is inject text. I write every inject myself.**

---

## 1. Competition framework

| Item | Detail |
|---|---|
| Format | Individual blue-team defense. **Each person is their own team.** |
| Schedule (Sat Sep 26) | 9:00 setup · 9:30 opening remarks · **10:00 scoring starts** · **4:00 end** · 4:30 winners and red team debrief. Pizza at noon, and the clock keeps running. |
| Scoring | **50% service uptime** + **50% injects**. Valid incident reports earn points back. Reverts cost points (100, then 200, then 400 per box). |
| Red Team | Mostly trying to **turn off scored services** (HTTP, FTP, SSH, and so on). Assume they already have default creds. |
| Portals | auth.byuccdc.org (Authentik, get team #) → Proxmox (VM consoles), **Quotient** (scoring.byuccdc.org: injects, PCRs, service status), NetBird VPN. Discord for announcements and **revert tickets**. |

### Topology (x = my team number)

| Host | Role / OS | Public IP | Private IP | Login |
|---|---|---|---|---|
| **bedrock** | VyOS 2025.11 router, 1:1 NAT | 192.168.200+x.2 | 172.16.1.1 | vyos |
| **iron** | Ubuntu Server 18.04 | 192.168.200+x.10 | 172.16.1.10 | steve |
| **lapis** | Windows Server 2016 (likely AD/DNS) | 192.168.200+x.11 | 172.16.1.11 | steve |
| **redstone** | Rocky 9.6 + Splunk Enterprise 10.0.2 (**no scored services**, it's mine) | 192.168.200+x.12 | 172.16.1.12 | steve / admin (Splunk) |

Default password everywhere: `iyearn4theMines!` (Red Team knows it too.)
Gateway and shared DNS: 192.168.192.1 (192.168.192.0/18). Example: team 12 means the router WAN is 192.168.212.2.

**Scored services:** HTTP, SSH, FTP, AD/DNS, POP3. They can be on Windows or Linux, so find out which box runs what in the first 10 minutes.

**Allowed users (must exist, don't delete, nobody else should exist):**
Admins: `steve`, `alex`. Users: `enderman creeper villager zombie enderdragon irongolem chickenjockey ghast`

---

## 2. Rules to follow

- Injects are **PDF only**, named `team##_inject##.pdf`, submitted in Quotient **before the deadline** (late submissions get nothing).
- Use my **team number only** and never my real name. Don't tell anyone my team number.
- **No AI writing or editing of any part of an inject or incident report.** AI can help with the *task*, but the words are mine. Graders use AI detectors, and getting caught means zero points or a DQ.
- **No paid AI** and **nothing that needs an account or sign-in** (even free ones).
- Only open/public resources. Public GitHub notes and scripts are OK.
- Keep services **working with correct content** on their **public IPs**. Don't move them and don't re-IP anything.
- **Don't block IPs.** No "allow only the scoring engine" rules. Services must be reachable from any source.
- **Don't game the scoring check** (for example, a fake page that only matches the check means DQ).
- **Changed a scored user's password? Submit a PCR in Quotient.**
- Don't delete the listed users.
- **Don't disable Splunk forwarding to the Black Team indexer.**
- Don't scan or touch other teams. No outside help, no messaging anyone. Stay professional.
- Answer **every** inject. A partial answer still beats a blank one.
- Reverts are requested in Discord `#ticket` and cost points, so use them as a last resort.

---

## 3. Game plan (first 30 min)

1. **9:00–10:00 (setup):** log into Authentik and get the team #. Open Proxmox consoles for all 4 boxes, open Quotient and Discord, and install the AI tool.
2. **Before red team gets going:** on every box, change passwords, then take a backup, then remove rogue users and SSH keys, then check the firewall/NAT, then look for persistence.
3. **Submit PCRs** right after changing scored-user passwords.
4. **Start an IR log** (a text file with timestamp, box, what I saw, what I did) and **take screenshots of everything.** That's what the incident reports are built from.
5. Keep checking **Quotient service status**. When something goes red, fix it first and hunt second.

**New password plan:** pick one strong password for scored users (PCR it) and a different one for root/Administrator/vyos/Splunk admin. Write them on paper.

---

## 4. Commands cheat sheet

### Linux (iron = Ubuntu 18.04, redstone = Rocky 9.6)

| Goal | Command | Why |
|---|---|---|
| Become root | `sudo -i` | Everything needs it |
| Change a password | `passwd steve` / bulk: `echo 'user:NewPass' \| chpasswd` | Default creds are known to red team |
| List real users | `awk -F: '$3>=1000 \|\| $3==0' /etc/passwd` | Find extra accounts |
| Find UID 0 besides root | `awk -F: '$3==0' /etc/passwd` | Hidden root backdoor |
| Who has sudo | `getent group sudo wheel; cat /etc/sudoers; ls /etc/sudoers.d` | Remove unauthorized admins |
| Remove from sudo | `gpasswd -d user sudo` (Rocky: `wheel`) | Least privilege |
| Lock a rogue user | `usermod -L -s /usr/sbin/nologin baduser` | Reversible, safer than deleting |
| SSH keys | `ls -la /root/.ssh /home/*/.ssh; cat /home/*/.ssh/authorized_keys` | Red team persistence |
| Who is logged in | `w`, `who`, `last -a \| head` | Spot intruders |
| Kick a session | `pkill -9 -t pts/3` | Remove an attacker shell (check it isn't me first!) |
| Listening ports | `ss -tulpn` | What's exposed, and which process owns it |
| Live connections | `ss -tunp state established` | Reverse shells / C2 |
| Processes as a tree | `ps -ef --forest \| less` | A shell under www-data or apache is a web shell |
| Kill a process | `kill -9 <PID>` | Containment (record PID + cmdline first) |
| Services | `systemctl list-units --type=service --state=running` | Know what's running |
| Service status/logs | `systemctl status X` / `journalctl -xeu X` | Why is it down |
| Restart service | `systemctl restart apache2` (or nginx, vsftpd, dovecot, ssh) | Most common fix |
| Stop and disable rogue | `systemctl disable --now X` | Persistence removal |
| Cron persistence | `crontab -l -u root; ls -la /etc/cron*; cat /etc/crontab; ls /var/spool/cron/crontabs` | Red team favorite |
| systemd persistence | `ls -lt /etc/systemd/system/ /lib/systemd/system/ \| head -30` | New malicious units |
| Other persistence | `cat /etc/rc.local /etc/ld.so.preload; ls -la /etc/profile.d; cat ~/.bashrc` | Backdoors |
| Recently changed files | `find /etc /var/www /tmp /dev/shm /root /home -mmin -60 -type f 2>/dev/null` | What changed since start |
| Web shells | `grep -rlE "eval\(|base64_decode|system\(|shell_exec|passthru" /var/www` | PHP backdoors |
| SUID binaries | `find / -perm -4000 -type f 2>/dev/null` | Privesc paths |
| Auth log | Ubuntu `tail -f /var/log/auth.log` · Rocky `tail -f /var/log/secure` | Logins, sudo, brute force |
| Web logs | `tail -f /var/log/apache2/access.log` (or `/var/log/nginx/`, `/var/log/httpd/`) | Attacks on HTTP |
| Firewall (Ubuntu) | `ufw status verbose`; `ufw allow 22/tcp`; `ufw enable` | Host firewall |
| Firewall (Rocky) | `firewall-cmd --list-all`; `firewall-cmd --permanent --add-port=8000/tcp; firewall-cmd --reload` | Host firewall |
| Raw iptables check | `iptables -S; iptables -t nat -S` | Red team DROP rules |
| Backup configs | `tar czf /root/bk-$(date +%H%M).tgz /etc /var/www 2>/dev/null` | Rollback if I break it |
| Test a service locally | `curl -I http://localhost`, `nc -v localhost 21`, `nc -v localhost 110` | Confirm it answers |
| Config tests | `apachectl configtest`, `nginx -t`, `sshd -t` | Validate before restart |

### Windows (lapis = Server 2016, run PowerShell as Admin)

| Goal | Command | Why |
|---|---|---|
| Domain users | `Get-ADUser -Filter * \| select Name,Enabled` | Find extra accounts |
| Reset domain pw | `Set-ADAccountPassword steve -Reset -NewPassword (Read-Host -AsSecureString)` | Kill default creds |
| Local users (non-DC) | `Get-LocalUser` / `net user` | Same, local |
| Admin groups | `Get-ADGroupMember "Domain Admins"`, `"Administrators"`, `"Enterprise Admins"`, `"Schema Admins"` | Unauthorized admins |
| Remove from group | `Remove-ADGroupMember "Domain Admins" -Members baduser` | Least privilege |
| Disable account | `Disable-ADAccount baduser` / `net user Guest /active:no` | Reversible |
| Listening ports | `netstat -ano \| findstr LISTEN` then `Get-Process -Id <PID>` | What's exposed |
| Connections | `Get-NetTCPConnection -State Established` | C2 / attackers |
| Services | `Get-Service \| ? Status -eq Running` / `sc.exe qc <name>` | Rogue services |
| Service binary paths | `Get-CimInstance Win32_Service \| select Name,PathName,StartMode` | Malicious paths in Temp/ProgramData |
| Scheduled tasks | `Get-ScheduledTask \| ? {$_.TaskPath -notlike "\Microsoft*"}` | Persistence |
| Run keys | `Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` (also HKCU, RunOnce) | Persistence |
| Startup folder | `dir "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"` | Persistence |
| Firewall on | `Set-NetFirewallProfile -All -Enabled True` | Host firewall |
| Firewall rules | `Get-NetFirewallRule -Enabled True -Direction Inbound \| select DisplayName,Action` | Spot rogue allow/block |
| Defender | `Set-MpPreference -DisableRealtimeMonitoring $false; Start-MpScan -ScanType QuickScan` | Catch malware |
| Disable SMBv1 | `Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force` | EternalBlue |
| Kill process | `Stop-Process -Id <PID> -Force` | Containment |
| Security log | `Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624,4625,4720,4732} -MaxEvents 50` | Logins and new users |
| IIS restart | `iisreset` / `Get-Website` | HTTP fix |
| DNS check | `Get-Service DNS,NTDS,Netlogon,KDC`; `nslookup <domain> 127.0.0.1` | AD/DNS scored |
| Password policy | `net accounts /minpwlen:12 /lockoutthreshold:5` (domain: GPMC Default Domain Policy) | Common inject |
| Policy refresh | `gpupdate /force` | Apply GPO |

**Key Event IDs:** 4624 logon OK · 4625 logon fail · 4720 user created · 4722 enabled · 4724 pw reset · 4728/4732/4756 added to group · 4698 sched task created · 7045 service installed · 1102 log cleared · 4688 process created

### VyOS (bedrock)

| Goal | Command |
|---|---|
| Enter config mode | `configure` |
| Show everything | `show` (in config) / `show configuration commands` (op mode) |
| Change password | `set system login user vyos authentication plaintext-password 'NEW'` then `commit` then `save` |
| Check NAT (1:1) | `show nat source rules`, `show nat destination rules`, or `show configuration commands \| grep nat` |
| Check firewall | `show firewall` / `show configuration commands \| grep firewall` |
| Delete a bad rule | `delete firewall ... rule N` then `commit` then `save` |
| SSH only on LAN | `set service ssh listen-address 172.16.1.1` then `commit` then `save` |
| Other users | `show configuration commands \| grep login` |
| Undo | `rollback N` (see `show system commit`) or `exit discard` |

### Splunk (redstone, web at http://172.16.1.12:8000)

```
index=* | stats count by host, sourcetype                          # who's sending logs
index=* (EventCode=4720 OR EventCode=4732 OR EventCode=4728)        # new users / admin adds
index=* EventCode=4625 | stats count by Account_Name, Source_Network_Address
index=* EventCode=7045 OR EventCode=4698                            # new service / sched task
index=* EventCode=1102                                               # log cleared
index=* sourcetype=linux_secure ("Accepted" OR "Failed password")  | stats count by src, user
index=* "sudo" COMMAND                                               # sudo usage
index=* sourcetype=access_combined (cmd= OR "../" OR "union select" OR ".php?")
```

---

## 5. Approved AI tools (free and **no sign-in** only)

> The rule is: if you have to sign in or pay, it's off-limits. Don't paste inject text into AI for writing, and never paste AI wording into a submission. **If unsure, ask Black Team in Discord before using it.** Free-tier catalogs change, so verify each one works at 9 AM.

| Tool | How | Account? | Notes |
|---|---|---|---|
| **OpenCode** (plan A) | `curl -fsSL https://opencode.ai/install \| bash` then run `opencode`, and pick a **free Zen model** | No (keyless free models) | Agentic, reads files, runs commands. Free model list changes, so pick one labeled "free". Might not run on old Ubuntu 18.04 glibc, so run it **on my laptop** and SSH out if needed. |
| **Duck.ai** (DuckDuckGo AI Chat) | duck.ai in the browser | No | **Best backup.** Several models, private, zero install. |
| **ChatGPT logged-out** | chatgpt.com without logging in | No (must stay logged OUT) | Strong model. Don't sign in. |
| **Microsoft Copilot** | copilot.microsoft.com logged out | No | Limited without sign-in but works. |
| **Perplexity** | perplexity.ai logged out | No | Good for research-type inject tasks (like the Palo Alto research inject) with sources. |
| **Local model (Ollama + small model)** | `ollama run qwen2.5-coder:7b` on my laptop | No | Offline and 100% allowed, but weaker and needs a good laptop. Pull the model **before** 10 AM. |
| **Aider / Continue / Cline + local Ollama** | point at local Ollama | No | Agentic alternatives to OpenCode if its free tier dies. |

**NOT allowed:** claude.ai, Gemini if it forces sign-in, GitHub Copilot (needs an account), anything paid, and API keys (keys require an account).

**Is anything better than OpenCode?** For agentic "run this on the box" work, OpenCode (keyless) is the best no-account option. Pair it with **Duck.ai / logged-out ChatGPT in a browser tab** for quick questions, since those don't depend on anything installed on the VMs. Keep AI **off the competition VMs** if the install fails, and don't waste more than 5 minutes fighting an install.

### How I use the agent files
1. On the box (or my laptop), get the matching file:
   `curl -sO https://raw.githubusercontent.com/<me>/<repo>/main/agents/iron-ubuntu.md` (plus `AGENT-RULES.md`)
2. For OpenCode, save it as `AGENTS.md` in the folder where I launch `opencode` (it auto-loads). For browser chat, paste the file in as the first message.
3. Tell it: "Follow AGENTS.md. Start Phase 1. Show me each command before running it."

---

## 6. Files in this repo

| File | For |
|---|---|
| `README.md` | Me: overview, rules, commands, AI tools |
| `AGENT-RULES.md` | Every AI agent: hard rules, which it reads first |
| `agents/iron-ubuntu.md` | AI agent on the Ubuntu server |
| `agents/lapis-windows.md` | AI agent on the Windows Server / AD |
| `agents/redstone-splunk.md` | AI agent on Rocky + Splunk |
| `agents/bedrock-vyos.md` | Router hardening steps (mostly manual) |
| `scripts/linux-baseline.sh` | Read-only snapshot and backup (Linux) |
| `scripts/windows-baseline.ps1` | Read-only snapshot and backup (Windows) |
| `INJECT-CHECKLIST.md` | Formatting and required-section checklist (I write the content) |
| `IR-LOG.md` | Timestamped notes during the day, which become incident reports |
