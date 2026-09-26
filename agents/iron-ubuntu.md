# AGENT: iron (Ubuntu Server 18.04), 172.16.1.10 / public 192.168.200+x.10

**First read and obey `AGENT-RULES.md`.** Likely scored services here: HTTP (Apache/nginx), SSH, FTP (vsftpd/proftpd), POP3 (Dovecot). Confirm in step 1. Auth log: `/var/log/auth.log`. Splunk forwarder is in `/opt/splunkforwarder`, so don't touch it.

## Phase 1: harden (in this order)

### 1. Recon (read-only, run all at once)
```bash
sudo -i
hostname; ip a; ip r
ss -tulpn
systemctl list-units --type=service --state=running --no-pager
awk -F: '$3==0 || $3>=1000 {print $1,$3,$7}' /etc/passwd
getent group sudo adm; cat /etc/sudoers | grep -v '^#'; ls -la /etc/sudoers.d
w; last -a | head -20
ls -la /root/.ssh /home/*/.ssh 2>/dev/null
```
Report back: **which scored services run here (port, process, config path)**, users not on the allowed list, UID 0 accounts besides root, and sudoers entries beyond steve/alex.

### 2. Backup (before any change)
```bash
mkdir -p /root/.bk && tar czf /root/.bk/etc-$(date +%H%M).tgz /etc
tar czf /root/.bk/www-$(date +%H%M).tgz /var/www 2>/dev/null
# FTP/mail data if present: /srv/ftp, /home/*/Maildir, /var/mail
```

### 3. Passwords (ask the human for the new passwords)
```bash
passwd root
for u in steve alex enderman creeper villager zombie enderdragon irongolem chickenjockey ghast; do echo "$u:NEWPASS" | chpasswd; done
```
→ **Remind the human: submit a PCR in Quotient now.**

### 4. Users and privileges
- Lock unknown users: `usermod -L -s /usr/sbin/nologin <user>`. Don't delete them yet.
- Extra UID 0: lock it and report.
- sudo should be only steve and alex: `gpasswd -d <user> sudo`. Remove rogue `/etc/sudoers.d/*` lines (back up first) and any `NOPASSWD: ALL` for non-admins. Validate with `visudo -c`.
- Service accounts with a login shell (`www-data`, `ftp`, etc.) should get `usermod -s /usr/sbin/nologin <svc>`, unless that breaks the service.

### 5. SSH (`/etc/ssh/sshd_config`)
- Review every `authorized_keys` and remove keys the human doesn't recognize (back up first). Also check `AuthorizedKeysFile` in the config.
- Set `PermitRootLogin no`, `PermitEmptyPasswords no`, `MaxAuthTries 4`, `X11Forwarding no`.
- **Keep `PasswordAuthentication yes`**, because scoring logs in with passwords.
- Check for `Match` blocks or odd `ForceCommand` lines. Run `sshd -t && systemctl restart ssh`, then test a new login **before** closing the current session.

### 6. Service hardening (only for what exists)
- **vsftpd** (`/etc/vsftpd.conf`): `anonymous_enable=NO`, `local_enable=YES`, `write_enable=YES` (keep as-is if scoring needs uploads), `chroot_local_user=YES`, `allow_writeable_chroot=YES`. Check `/etc/ftpusers` doesn't block scored users. `systemctl restart vsftpd`.
- **Apache/nginx:** disable directory listing (`Options -Indexes`), check `/var/www` for web shells, don't change page content, and run `apachectl configtest`.
  ```bash
  grep -rlE "eval\(|base64_decode|system\(|shell_exec|passthru|assert\(" /var/www
  find /var/www -newer /etc/hostname -type f | head -50
  ```
  Upload dirs: no PHP execution. Report any shells to the human before removing (screenshot).
- **Dovecot (POP3):** `doveconf -n`. Keep plaintext auth working if that's how it's scored (`disable_plaintext_auth=no` may be required). Don't force SSL-only.
- **MySQL/MariaDB** (if a web dependency): don't break the app's DB creds. Check `mysql -e "select user,host from mysql.user"` for rogue users.
- Stop and disable clearly unneeded risky services (telnet, rsh, nfs, rpcbind, smb, xinetd, cups, avahi) after confirming they're not scored.

### 7. Host firewall (ufw), by port only, never by IP
```bash
ufw status verbose; iptables -S      # first look for red-team rules
ufw default deny incoming; ufw default allow outgoing
ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 21/tcp; ufw allow 110/tcp
ufw allow 40000:50000/tcp   # ONLY if vsftpd passive range is set to this (check pasv_min_port/pasv_max_port)
# Splunk forwarder is outbound (9997), so no inbound rule is needed
ufw enable
```
Match the allow list to what step 1 found (add 995, 3306-local-only, etc. as needed). Then verify each service from localhost.

### 8. Persistence sweep
```bash
crontab -l; for u in $(cut -d: -f1 /etc/passwd); do crontab -l -u $u 2>/dev/null | sed "s/^/$u: /"; done
cat /etc/crontab; ls -la /etc/cron.* /var/spool/cron/crontabs
systemctl list-timers --all --no-pager
ls -lt /etc/systemd/system /lib/systemd/system | head -40
cat /etc/rc.local /etc/ld.so.preload 2>/dev/null
ls -la /etc/profile.d; tail -5 /root/.bashrc /home/*/.bashrc
find / -perm -4000 -type f 2>/dev/null     # compare against a normal list; flag odd ones (e.g. /tmp, find, vim, python with SUID)
ls -la /tmp /var/tmp /dev/shm
ps -ef --forest | grep -vE '\[.*\]'
ss -tunp state established
```

### 9. Quick kernel/sysctl wins (safe)
```bash
sysctl -w net.ipv4.tcp_syncookies=1 net.ipv4.conf.all.accept_redirects=0 net.ipv4.conf.all.send_redirects=0
```
Known 18.04 privesc risks: pkexec (PwnKit, CVE-2021-4034), so `chmod 0755 /usr/bin/pkexec` (removes SUID; safe). Also old sudo (Baron Samedit). Patch only with `apt install --only-upgrade sudo` if repos work and the human approves.

### 10. Set up auditd (optional, if installable)
`apt install auditd -y`, then add `-w /etc/passwd -p wa -k users`, `-w /etc/sudoers -p wa -k sudo`, `-w /root/.ssh -p wa -k sshkeys`, `-w /var/www -p wa -k web`.

## Phase 2: hunt loop (every ~20 min)
`w` → `ss -tulpn` → `ss -tunp state established` → `ps -ef --forest` → new users (`tail /etc/passwd`) → crontabs → `grep -E "Accepted|Failed|sudo" /var/log/auth.log | tail -30` → web access log for `cmd=`, `../`, odd POSTs → `systemctl status` for each scored service.

## Scenarios
| Symptom | Do this |
|---|---|
| Web down | `systemctl status apache2`/`nginx` → `journalctl -xeu` → `configtest` → check ufw/iptables → check `/var/www` content vs backup → restore from `/root/.bk` |
| Web content defaced | Restore from `/root/.bk/www-*.tgz` (screenshot the defacement first), find the write vector (upload form, FTP, web shell) |
| SSH down | `sshd -t` → check config and `ss -tlpn \| grep 22` → `ufw status` → `/etc/hosts.deny` → restart |
| FTP login fails | Password changed? (PCR) → `/etc/ftpusers` / `vsftpd.user_list` → shell in `/etc/shells` → `userlist_enable` → passive ports firewall |
| POP3 fails | `systemctl status dovecot` → `doveconf -n` → `nc localhost 110` → mail dir permissions |
| Unknown process / reverse shell | Record PID, parent, and cmdline (`ls -l /proc/PID/exe`, `cat /proc/PID/cmdline`), hash the binary, screenshot, then kill it, remove the binary and persistence, and log it in IR-LOG |
| New user appeared | Lock it, check who created it (auth.log), check their SSH keys and crontab, log it |
| Everything stopped scoring at once | Probably the router or firewall. Check `iptables -S` here, then bedrock (see bedrock-vyos.md) |
| Locked out | Use the Proxmox console. Last resort is a revert (costs points). |
