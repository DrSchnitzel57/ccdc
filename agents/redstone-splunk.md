# AGENT: redstone (Rocky Linux 9.6 + Splunk Enterprise 10.0.2), 172.16.1.12 / public 192.168.200+x.12

**First read and obey `AGENT-RULES.md`.** This box has **no scored services**. It's the defender's SIEM. iron and lapis forward logs here (and to a Black Team indexer, which must never be disabled). Goals: keep Splunk up and receiving, lock it down, and use it to hunt red team. Auth log: `/var/log/secure`. Firewall: firewalld. SELinux should be enforcing.

## Phase 1: harden

### 1. Recon
```bash
sudo -i
ss -tulpn; systemctl list-units --type=service --state=running --no-pager
awk -F: '$3==0 || $3>=1000 {print $1,$3,$7}' /etc/passwd
getent group wheel; ls -la /etc/sudoers.d; ls -la /root/.ssh /home/*/.ssh 2>/dev/null
getenforce; firewall-cmd --list-all
ls /opt/splunk/bin && /opt/splunk/bin/splunk status
```
Splunk ports: **8000** web, **8089** management (REST), **9997** receiving (forwarders), 8088 HEC (if used).

### 2. Backup
```bash
tar czf /root/etc-$(date +%H%M).tgz /etc
tar czf /root/splunk-etc-$(date +%H%M).tgz /opt/splunk/etc
```

### 3. Passwords (ask the human)
```bash
passwd root; passwd steve; passwd alex   # other listed users too (PCR if they're on the scored list)
/opt/splunk/bin/splunk edit user admin -password 'NEWPASS' -auth admin:'iyearn4theMines!'
```
Then Splunk Web → Settings → Users: remove or disable any unknown Splunk users and check roles (only admin should have the `admin` role).

### 4. Users, sudo, SSH
Same as Linux: lock unknown users (`usermod -L -s /sbin/nologin`), keep wheel to steve and alex only, check authorized_keys, and in `/etc/ssh/sshd_config` set `PermitRootLogin no` → `sshd -t && systemctl restart sshd`. `setenforce 1` if it's permissive (then set `SELINUX=enforcing` in `/etc/selinux/config`).

### 5. Firewall, by port only
```bash
firewall-cmd --permanent --remove-service=cockpit 2>/dev/null
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=8000/tcp --add-port=9997/tcp
# 8089 mgmt: leave it closed from outside unless needed (not a scored service)
firewall-cmd --reload; firewall-cmd --list-all
```
Check for red-team rules: `nft list ruleset | head -80`.

### 6. Splunk-specific hardening
- Confirm receiving is on: `/opt/splunk/bin/splunk list inputs` or Settings → Forwarding and receiving → Receive data → 9997 enabled.
- Look for malicious apps (red team can get RCE via uploaded apps or scripted inputs): `ls -lt /opt/splunk/etc/apps/` shows anything new or odd. Also check `grep -r "script" /opt/splunk/etc/apps/*/local/inputs.conf /opt/splunk/etc/system/local/inputs.conf`.
- Check `/opt/splunk/etc/system/local/` for unexpected `authentication.conf` / `web.conf` changes.
- Splunk should run as the `splunk` user, not root: `ps -o user= -p $(pgrep -f splunkd | head -1)`.
- Restart if needed: `/opt/splunk/bin/splunk restart`.

### 7. Persistence sweep
Cron (`crontab -l`, `/etc/cron*`, `/var/spool/cron/`), `systemctl list-timers`, `/etc/systemd/system`, `/etc/rc.d/rc.local`, `/etc/ld.so.preload`, `.bashrc`, SUID (`find / -perm -4000`), `/tmp /dev/shm`, `ps -ef --forest`, and `ss -tunp state established`.

## Phase 2: hunting with Splunk (paste into Search, time range "Last 60 minutes")

```
| tstats count where index=* by host, index, sourcetype          # what data exists (verify iron + lapis are reporting)
index=* EventCode=4720 | table _time host SAM_Account_Name Subject_Account_Name   # user created
index=* (EventCode=4728 OR EventCode=4732 OR EventCode=4756) | table _time host Group_Name Member_Name Subject_Account_Name
index=* EventCode=4625 | stats count by Account_Name Source_Network_Address | sort -count   # brute force
index=* EventCode=4624 (Logon_Type=3 OR Logon_Type=10) | stats count by Account_Name Source_Network_Address
index=* (EventCode=7045 OR EventCode=4698) | table _time host Service_Name Task_Name Service_File_Name
index=* EventCode=1102 OR EventCode=104                          # logs cleared
index=* EventCode=4688 | table _time host New_Process_Name Process_Command_Line   # if cmdline auditing on
index=* source="*auth.log" OR source="*secure" ("Accepted" OR "Failed password") | rex "from (?<src>\d+\.\d+\.\d+\.\d+)" | stats count by host src
index=* source="*auth.log" "sudo:" COMMAND | table _time host _raw
index=* source="*access*" ("cmd=" OR "../" OR "/etc/passwd" OR "union select" OR "wget" OR "curl" OR "whoami")
index=* useradd OR "new user" OR usermod
```
If the Windows field names differ, click an event and use the fields shown in the left sidebar. Save useful searches (Save As → Alert, real-time) for new users and log clears.

**For incident reports:** have the human screenshot the Splunk event (timestamp, host, source IP, user). Give the facts (time, host, IP, account, technique, MITRE ID such as T1136 Create Account, T1053 Scheduled Task, T1098 SSH authorized_keys, T1505.003 Web Shell). **Do not write the report text.**

## Scenarios
| Symptom | Do this |
|---|---|
| No data from a host | On that host: forwarder running? (`/opt/splunkforwarder/bin/splunk status`, Windows `Get-Service SplunkForwarder`) → host firewall outbound → here: 9997 open and listening (`ss -tlnp \| grep 9997`) |
| Splunk web down | `/opt/splunk/bin/splunk status` → `restart` → `tail /opt/splunk/var/log/splunk/splunkd.log` → disk full? (`df -h`) |
| Can't log in to Splunk | Reset: stop splunk → `mv /opt/splunk/etc/passwd /opt/splunk/etc/passwd.bak` → create `/opt/splunk/etc/system/local/user-seed.conf` with `[user_info]` `USERNAME = admin` `PASSWORD = <new>` → start |
| Odd app in apps dir | Record and screenshot it → disable it (`/opt/splunk/bin/splunk disable app <name>`) → restart → log it |
