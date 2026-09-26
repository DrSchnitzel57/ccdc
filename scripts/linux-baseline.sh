#!/bin/bash
# Read-only baseline snapshot + config backup. Changes NOTHING on the system.
# Usage: sudo bash linux-baseline.sh   -> writes /root/baseline-HHMM/
# Run at start, then re-run later and diff:  diff -r /root/baseline-0905 /root/baseline-1130
T=$(date +%H%M); D=/root/baseline-$T; mkdir -p "$D"
cp /etc/passwd /etc/group /etc/shadow "$D"/ 2>/dev/null
ss -tulpn                                   > "$D/listening.txt"
ss -tunp state established                  > "$D/established.txt"
ps -eo user,pid,ppid,lstart,cmd --forest    > "$D/processes.txt"
systemctl list-units --type=service --all --no-pager > "$D/services.txt"
systemctl list-unit-files --state=enabled --no-pager > "$D/enabled.txt"
systemctl list-timers --all --no-pager      > "$D/timers.txt"
for u in $(cut -d: -f1 /etc/passwd); do c=$(crontab -l -u "$u" 2>/dev/null); [ -n "$c" ] && echo "== $u" && echo "$c"; done > "$D/crontabs.txt"
ls -la /etc/cron* /var/spool/cron 2>/dev/null > "$D/cron-dirs.txt"
cat /etc/crontab >> "$D/cron-dirs.txt"
for h in /root /home/*; do [ -f "$h/.ssh/authorized_keys" ] && echo "== $h" && cat "$h/.ssh/authorized_keys"; done > "$D/authorized_keys.txt"
cat /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v '^#' | grep -v '^$' > "$D/sudoers.txt"
find / -perm -4000 -type f 2>/dev/null      > "$D/suid.txt"
(iptables -S; iptables -t nat -S; command -v ufw >/dev/null && ufw status verbose; command -v firewall-cmd >/dev/null && firewall-cmd --list-all) > "$D/firewall.txt" 2>&1
ls -la /tmp /var/tmp /dev/shm               > "$D/tmp.txt" 2>&1
cat /etc/rc.local /etc/ld.so.preload        > "$D/rc-preload.txt" 2>&1
tar czf "$D/etc.tgz" /etc 2>/dev/null
[ -d /var/www ] && tar czf "$D/www.tgz" /var/www 2>/dev/null
echo "[+] Baseline saved to $D"
echo "[!] Non-allowed users with UID>=1000 or UID 0:"
awk -F: '($3>=1000 && $3<65534) || $3==0 {print $1}' /etc/passwd | grep -vxE 'root|steve|alex|enderman|creeper|villager|zombie|enderdragon|irongolem|chickenjockey|ghast'
