# bedrock (VyOS 2025.11 router), WAN 192.168.200+x.2 / LAN 172.16.1.1

**Obey `AGENT-RULES.md`.** No AI agent will run on the router. Do this by hand in the Proxmox console, and paste output to the AI if help is needed. **The router does 1:1 NAT for every box, so if it breaks, EVERYTHING stops scoring.** Never change NAT or addressing, and never add IP-based blocks.

## Phase 1 (5 minutes)
```
# op mode: capture the baseline FIRST (screenshot or save it)
show configuration commands | no-more
show interfaces
show nat destination rules
show nat source rules
show system commit

configure
# 1. Password
set system login user vyos authentication plaintext-password 'NEWPASS'
# 2. Remove any unknown login users
show system login
# delete system login user <baduser>
# 3. SSH on the LAN side only (not scored). Router is still manageable from the Proxmox console.
set service ssh listen-address 172.16.1.1
set service ssh disable-password-authentication   # ONLY if you use keys; otherwise skip this line
# 4. Turn off services you don't need (check which exist first)
show service
# delete service telnet / delete service https (if API/GUI enabled and unused)
commit
save
exit
```
If a commit breaks things: `configure` → `rollback <N>` (from `show system commit`) → `commit` → `save`.

## What red team does to routers
- Adds a firewall rule that drops traffic to a box or port. Look in `show firewall` and `show configuration commands | grep -E "firewall|drop|reject"`.
- Deletes or changes a NAT rule so a box's public IP stops working. Compare `show nat destination rules` / `show nat source rules` to the baseline.
- Adds a user or SSH key: `show configuration commands | grep -E "login|public-keys"`.
- Adds a task-scheduler job: `show configuration commands | grep task-scheduler`.

## If everything stops scoring at once
1. `show interfaces`: are both interfaces up with the right IPs?
2. `ping 192.168.192.1`: is the gateway reachable?
3. Check the NAT and firewall rules against the baseline and delete the rogue rules, then `commit` and `save`.
4. `show system commit` shows when the change happened, which is useful for the incident report.
5. Screenshot everything before you fix it.
