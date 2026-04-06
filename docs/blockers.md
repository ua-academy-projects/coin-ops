# Blockers and Workarounds

Issues encountered during environment setup, documented per the ТЗ requirement to actively share platform-specific fixes.

---

## 1. Hyper-V does not support Vagrant static IP assignment

**Symptom:** Running `vagrant up` with a static IP in the `Vagrantfile` (e.g. `config.vm.network "private_network", ip: "172.31.1.10"`) fails or is silently ignored on Hyper-V. The VM boots with a DHCP-assigned address that changes on every `vagrant halt && vagrant up`.

**Root cause:** The VirtualBox driver supports host-only adapters with static IPs natively. Hyper-V's external/internal switches use DHCP by default, and Vagrant has no mechanism to configure Hyper-V DHCP reservations.

**Workaround — set static IP inside the VM via netplan (one-time per VM):**

```bash
# Step 1 — find the current DHCP address
#   Either: vagrant ssh-config
#   Or in PowerShell: Get-VM | Select Name, @{n="IP";e={$_.NetworkAdapters.IPAddresses}}

# Step 2 — SSH into the VM
vagrant ssh   # or: ssh vagrant@<dhcp-ip>

# Step 3 — remove the Vagrant-managed netplan config (conflicts with static config)
sudo rm /etc/netplan/01-netcfg.yaml

# Step 4 — write a static config
sudo tee /etc/netplan/00-installer-config.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 172.31.1.10/20
      routes:
        - to: default
          via: 172.31.0.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

# Step 5 — apply
sudo netplan apply

# Step 6 — set hostname
sudo hostnamectl set-hostname softserve-node-01

# Step 7 — exit and reconnect on the new IP
exit
ssh vagrant@172.31.1.10
```

Repeat for node-02 (`172.31.1.11`) and node-03 (`172.31.1.12`).

**After this:** IPs are permanent across reboots and `vagrant reload`. Ansible uses hostnames from the Windows `hosts` file.

---

## 2. `01-netcfg.yaml` conflicts with static netplan config

**Symptom:** After writing a static IP config to `00-installer-config.yaml` and running `sudo netplan apply`, the VM reverts to DHCP on next boot. The static config appears to have no effect.

**Root cause:** Vagrant writes `/etc/netplan/01-netcfg.yaml` on first boot, configuring the primary interface with DHCP. Because netplan applies configs in lexicographic order, `01-netcfg.yaml` (DHCP) overrides `00-installer-config.yaml` (static) — the higher-numbered file wins for conflicting settings.

**Workaround:** Delete `01-netcfg.yaml` before writing the static config (covered in step 3 above). Alternatively, name the static config `99-static.yaml` so it sorts last.

---

## 3. `gateway4` is deprecated in Ubuntu 24.04 netplan

**Symptom:** Running `sudo netplan apply` with a config that uses `gateway4`:
```yaml
network:
  ethernets:
    eth0:
      gateway4: 172.31.0.1   # ← this syntax
```
Produces:
```
WARNING: `gateway4` has been deprecated, use default routes instead.
```
The config may still apply, but future Ubuntu versions will drop support.

**Workaround:** Use the `routes` stanza instead:
```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 172.31.1.10/20
      routes:
        - to: default
          via: 172.31.0.1
      nameservers:
        addresses: [8.8.8.8]
```
This is the correct syntax for Ubuntu 24.04 and later.

---

## 4. Ansible `community.rabbitmq` collection may not be installed

**Symptom:** `ansible-playbook provision.yml` fails with:
```
ERROR! couldn't resolve module/action 'community.rabbitmq.rabbitmq_user'
```

**Root cause:** The `community.rabbitmq` Ansible collection is not installed by default. It ships separately from `ansible-core`.

**Workaround — option A (install collection):**
```bash
ansible-galaxy collection install community.rabbitmq
```

**Workaround — option B (shell fallback already in provision.yml):**
`provision.yml` includes a `shell` task fallback using `rabbitmqctl` directly. It runs unconditionally with `changed_when: false` so it's safe to re-run. The `community.rabbitmq` task has `ignore_errors: yes`.

---

## 5. Hyper-V Default Switch changes subnet on every Windows reboot

**Symptom:** After rebooting Windows, VMs lose internet access and Ansible can no longer reach them by IP. The VMs themselves still have their static IPs (netplan is untouched), but their default gateway (`172.31.0.1`) no longer exists because the Default Switch moved to a different subnet.

**Root cause:** Hyper-V's Default Switch is designed for Docker/WSL NAT access and deliberately reassigns its subnet on every boot. It is not intended for VMs that need stable networking.

**Workaround — create a dedicated Internal Switch with static NAT (one-time, persists forever):**

```powershell
# PowerShell as Administrator

# 1. Create internal switch
New-VMSwitch -Name "CoinOpsSwitch" -SwitchType Internal

# 2. Assign the gateway IP (matches what VMs already expect)
New-NetIPAddress -IPAddress 172.31.0.1 -PrefixLength 20 `
    -InterfaceAlias "vEthernet (CoinOpsSwitch)"

# 3. Create NAT for internet access
New-NetNat -Name "CoinOpsNAT" -InternalIPInterfaceAddressPrefix "172.31.0.0/20"

# 4. Attach all VMs to the new switch
Connect-VMNetworkAdapter -VMName "softserve-node-01" -SwitchName "CoinOpsSwitch"
Connect-VMNetworkAdapter -VMName "softserve-node-02" -SwitchName "CoinOpsSwitch"
Connect-VMNetworkAdapter -VMName "softserve-node-03" -SwitchName "CoinOpsSwitch"
```

Then reload VMs:
```powershell
vagrant reload
```

**Note:** `vswitch_name` in the Vagrantfile Hyper-V provider block does not exist in current Vagrant versions. The `Connect-VMNetworkAdapter` PowerShell command is the correct way to assign the switch.

---

## 6. WSL cannot reach Hyper-V VM network without routing

**Symptom:** Ansible runs from WSL but cannot ping or SSH to VMs at `172.31.1.x`. WSL's network (`172.31.32.0/20`) and the VM network (`172.31.0.0/20`) are on different subnets with no route between them.

**Root cause:** WSL2 runs on its own virtual NAT switch (`vEthernet (WSL)`). It has no automatic route to other Hyper-V virtual switch networks.

**Workaround:**

In WSL — add route and make it permanent:
```bash
sudo ip route add 172.31.0.0/20 via 172.31.32.1

# Persist across WSL restarts
echo '[boot]
command = "ip route add 172.31.0.0/20 via 172.31.32.1"' | sudo tee /etc/wsl.conf
```

In PowerShell (Admin) — enable packet forwarding between interfaces:
```powershell
Set-NetIPInterface -InterfaceAlias "vEthernet (WSL)" -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias "vEthernet (CoinOpsSwitch)" -Forwarding Enabled
```

The forwarding setting persists across reboots. The WSL route is restored automatically via `/etc/wsl.conf`.

---

## 7. Ansible `become_user: postgres` fails — `acl` package missing

**Symptom:** `provision.yml` fails when creating the PostgreSQL user:
```
Failed to set permissions on the temporary files Ansible needs to create
when becoming an unprivileged user (rc: 1, err: chmod: invalid mode: 'A+user:postgres:rx:allow')
```

**Root cause:** Ansible uses POSIX ACLs to set permissions on temp files when switching to an unprivileged user (`become_user`). The `acl` package providing `setfacl` is not installed by default on Ubuntu 24.04.

**Workaround:** Install `acl` before any `become_user` tasks:
```yaml
- name: Install acl
  apt:
    name: acl
    state: present
```

Already added to `provision.yml` for the history node.

---

## 8. Ansible `group_vars/secrets.yml` silently ignored

**Symptom:** Ansible fails with `'rabbitmq_password' is undefined` even though `ansible/group_vars/secrets.yml` exists and contains the variable.

**Root cause:** Ansible only auto-loads `group_vars/` files whose **filename matches a group name** in the inventory. A file named `secrets.yml` is silently ignored because there is no group called `secrets`.

**Workaround:** Place files inside a directory named after the group instead:
```
ansible/group_vars/
└── all/           ← directory named after the "all" group
    ├── main.yml
    └── secrets.yml   ← now loaded because it's inside all/
```

Ansible loads every `.yml` file inside `group_vars/<groupname>/`.

---

## 9. PostgreSQL refuses connections via external IP from services on same VM

**Symptom:** History consumer and API crash on startup with:
```
connection to server at "172.31.1.10", port 5432 failed: Connection refused
```

**Root cause:** PostgreSQL binds to `127.0.0.1` (loopback) by default. Connecting via the VM's external IP (`172.31.1.10`) is refused even from the same machine.

**Workaround:** Use `localhost` in `DATABASE_URL` for services running on the same VM as PostgreSQL:
```yaml
# ansible/group_vars/all/main.yml
database_url: "postgresql://{{ db_user }}:{{ db_password }}@localhost:5432/{{ db_name }}"
```

The `rabbitmq_url` intentionally keeps `172.31.1.10` because the proxy service on node-02 connects to RabbitMQ on node-01 over the network — that connection is external and correct.

---

## 10. Polymarket Data API field names differ from documentation

**Symptom:** Whale tracker shows empty positions for all traders. Proxy logs show "Whale cache updated: 20 whales" (leaderboard works) but every whale has `positions: []`.

**Root cause:** The actual Polymarket Data API returns different field names than what the spec described. The Go structs were built from the spec, not from the real API response.

| Spec said | API actually returns |
|-----------|---------------------|
| `address` | `proxyWallet` |
| `pseudonym` | `userName` |
| `volume` | `vol` |
| `rank` (int) | `rank` (string `"1"`, `"2"`, ...) |
| `market` | `title` |
| `avgPrice` | `curPrice` |

Additionally, the `slug` field is already present in the positions response — the title→slug mapping built from the markets endpoint was unnecessary.

**How it was found:** curling the Data API directly and comparing raw JSON to Go struct tags.

**Fix:** Updated `LeaderboardEntry` and `PositionEntry` structs in `proxy/main.go` to match actual field names. Removed the `fetchMarkets()` call from `fetchAndUpdateCache()` since slug resolution is no longer needed.

**Lesson:** Always validate API responses against actual data before writing structs. Specs and docs lag behind real API behavior.

---

## 11. Go build fails without network access during `go mod download`

**Symptom:** `go build` on node-02 fails with:
```
go: github.com/rabbitmq/amqp091-go@v1.10.0: dial tcp: connection refused
```

**Root cause:** The VM cannot reach the internet (proxy, firewall, or DNS misconfiguration).

**Workaround:**
1. Verify DNS: `nslookup proxy.golang.org`
2. Verify HTTP access: `curl -I https://proxy.golang.org`
3. If behind a corporate proxy, set `HTTPS_PROXY` in the Ansible task environment or in `/etc/environment`.
4. Alternatively, build the binary locally with `make build` (cross-compiles to Linux amd64) and add a copy task to `ansible/roles/proxy/tasks/main.yml` to upload the binary instead of building on the VM.

---

## 13. Terraform Hyper-V provider: "Either dynamic or static must be selected"

**Symptom:** `terraform apply` fails for all three VM resources:
```
Error: [ERROR][hyperv][create] Either dynamic or static must be selected
  with hyperv_machine_instance.node["node-01"]
```

**Root cause:** The `taliesins/hyperv` provider requires an explicit MAC address policy on every `network_adaptors` block. Leaving both `dynamic_mac_address` and `static_mac_address` absent (not just omitted — even setting `dynamic_mac_address = true` or `static_mac_address = ""` alone does not satisfy the validator) causes the provider to fail at create time with this non-obvious error.

**Fix:** Both fields must be present simultaneously — set static MAC and explicitly set `dynamic_mac_address = false`. Also replace `dynamic_memory = false` with `static_memory = true` (same provider quirk — the boolean must be affirmed, not negated):
```hcl
static_memory = true   # not dynamic_memory = false

vm_firmware {
  enable_secure_boot   = "On"    # not true — provider expects "On"/"Off" strings
  secure_boot_template = "MicrosoftUEFICertificateAuthority"
}

network_adaptors {
  name                = "eth0"
  switch_name         = hyperv_network_switch.internal.name
  static_mac_address  = each.value.mac   # e.g. "00:15:5D:01:00:01"
  dynamic_mac_address = false            # must be explicit, not absent
}
```
The `locals.nodes` map includes a `mac` field per node. Static MACs are stable across `terraform destroy && apply` cycles.

---

## 14. VM fails to boot: "The signed image's hash is not allowed (DB)"

**Symptom:** Hyper-V Virtual Machine Connection shows the UEFI Boot Summary:
```
3. SCSI Disk (0,0)  The signed image's hash is not allowed (DB)
No operating system was loaded.
```

**Root cause:** Hyper-V Generation 2 VMs have Secure Boot enabled with the default `MicrosoftWindows` template. This template only trusts Microsoft-signed bootloaders. Ubuntu uses Canonical's UEFI signing certificate, which is not in the `MicrosoftWindows` template's DB (allowed signatures database).

**Fix:** Switch the Secure Boot template to `MicrosoftUEFICertificateAuthority` in `vms.tf`. This template includes both Microsoft's and Canonical's signing certs:
```hcl
vm_firmware {
  enable_secure_boot   = true
  secure_boot_template = "MicrosoftUEFICertificateAuthority"
}
```
Disabling Secure Boot entirely (`enable_secure_boot = false`) also works but is less correct for a production-like setup.

---

## 15. cloud-init network: wrong subnet mask and gateway

**Symptom:** VMs boot but cannot reach the Windows host or internet. WSL cannot SSH to VMs. The VMs have correct IPs (`172.31.1.x`) but routing fails.

**Root cause:** cloud-init `network-config` files used `/24` mask and `via: 172.31.1.1` (no machine exists at this address). The Windows host's virtual NIC on the Internal switch is at `172.31.0.1` on a `/20` network. With a `/24` mask the VMs are on `172.31.1.0/24` and the host is on `172.31.0.0/24` — different subnets, no route between them.

**Fix:** Use `/20` mask and the correct gateway in all three `network-config` files:
```yaml
addresses:
  - 172.31.1.10/20     # was /24
routes:
  - to: default
    via: 172.31.0.1    # was 172.31.1.1 — host's vNIC address
```
With `/20` all addresses `172.31.0.0`–`172.31.15.255` are on the same subnet, so VMs can reach the host at `172.31.0.1` without a separate route.

---

## 12. Ansible SSH fails with "UNPROTECTED PRIVATE KEY FILE" on WSL

**Symptom:** `ansible all -m ping` fails with "Warning: Unprotected private key file" and UNREACHABLE.

**Root cause:** Windows NTFS permissions on the `.vagrant` folder are too permissive. WSL mounts Windows drives without enforcing Unix permissions. SSH refuses key files readable by other users.

**Workaround:**
```bash
chmod 600 /mnt/f/univ/softserv-internship/.vagrant/machines/*/hyperv/private_key
```

Must be re-run after each `vagrant up` since Vagrant regenerates keys with open permissions.

---

## 16. Go apt package too old for go-redis v9 (`maps`/`slices` not in GOROOT)

**Symptom:** Proxy build on node-02 fails during `ansible-playbook deploy.yml`:
```
/root/go/pkg/mod/github.com/redis/go-redis/v9@v9.18.0/command.go:7:2:
  package maps is not in GOROOT (/usr/lib/go-1.18/src/maps)
/root/go/pkg/mod/github.com/redis/go-redis/v9@v9.18.0/maintnotifications/hooks.go:5:2:
  package slices is not in GOROOT (/usr/lib/go-1.18/src/slices)
```

**Root cause:** `apt install golang-go` on Ubuntu 22.04 installs Go 1.18. The `go-redis/v9` library requires Go 1.21+ because it imports the `maps` and `slices` packages from the standard library, which were only added in Go 1.21. `go.mod` declares `go 1.21` but the provision playbook was installing from apt without checking the version.

**Fix:** Install Go 1.22 by downloading the official binary tarball directly instead of using apt:
```yaml
- name: Download Go 1.22 binary
  get_url:
    url: https://go.dev/dl/go1.22.1.linux-amd64.tar.gz
    dest: /tmp/go.tar.gz

- name: Remove old Go installation
  file:
    path: /usr/local/go
    state: absent

- name: Extract Go to /usr/local
  unarchive:
    src: /tmp/go.tar.gz
    dest: /usr/local
    remote_src: yes
```

**Lesson:** Never rely on distro package managers for language runtimes in production-like setups. Always pin the exact version and install from upstream.

---

## 17. Ansible `go build` fails: binary not found in non-login shell PATH

**Symptom:** Even after installing Go 1.22 to `/usr/local/go`, the deploy playbook fails:
```
fatal: [softserve-node-02]: FAILED! => {"cmd": ["go", "build", ...], "rc": 2,
  "msg": "No such file or directory"}
```

**Root cause:** Ansible connects via SSH without a login shell. `/etc/profile.d/go.sh` (which adds `/usr/local/go/bin` to `PATH`) is only sourced in interactive login shells. The `command: go build` task runs in a minimal environment where `$PATH` does not include `/usr/local/go/bin`.

**Fix:** Either use the absolute binary path, or explicitly set PATH in the task's `environment` block:
```yaml
- name: Build proxy binary
  command: /usr/local/go/bin/go build -mod=mod -o /opt/cognitor/proxy/proxy .
  environment:
    PATH: /usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    HOME: /root
    GOPATH: /root/go
```

---

## 18. Ansible `synchronize` + `delegate_to: localhost` inherits `become: yes`

**Symptom:** The UI deploy task fails:
```
fatal: [softserve-node-03 -> localhost]: FAILED! =>
  {"module_stderr": "sudo: a password is required\n"}
```

**Root cause:** The `synchronize` module is delegated to `localhost` to push the local `dist/` folder to the remote VM. But the play has `become: yes` at the top level, which the task inherits. Ansible then tries to run `sudo rsync` on localhost — where there is no passwordless sudo configured.

**Fix:** Add `become: false` explicitly to the synchronize task to override the play-level setting:
```yaml
- name: Sync React dist/ to web root
  synchronize:
    src: "{{ playbook_dir }}/../ui-react/dist/"
    dest: /var/www/coin-ops/
  delegate_to: localhost
  become: false          # ← required: overrides play-level become: yes
```

---

## 19. React app contained unused AI/server dependencies from template

**Symptom:** `npm ci` installs `@google/genai`, `express`, `dotenv`, `tsx`, `@types/express` — none of which are imported anywhere in the application code. Build time is inflated and `npm audit` reports unnecessary attack surface.

**Root cause:** The UI was scaffolded from an AI Studio template that included a local Express server (for proxying Gemini API calls) and Gemini client libraries. When the app was rewired to use the real backend APIs, the template dependencies were not removed.

**Fix:** Remove from `package.json`:
```diff
- "@google/genai": "^1.29.0",
- "express": "^4.21.2",
- "dotenv": "^17.2.3",
```
```diff
devDependencies:
- "@types/express": "^4.17.21",
- "tsx": "^4.21.0",
```

**How to catch this earlier:** Run `npx depcheck` before committing UI changes. It reports any package listed in `package.json` that is not imported in the source code.

---

## 20. Terraform cloud-init ISO attached as hard disk instead of DVD drive

**Symptom:** VMs boot but cloud-init never runs. The hostname, SSH key, and static IP are not applied. The VM gets a random DHCP address and the default `ubuntu` hostname.

**Root cause:** The initial Terraform config attached the seed ISO using a `hard_disk_drives` block. Hyper-V Generation 2 enforces a strict distinction: ISOs can only be mounted as optical media via `dvd_drives`. Attaching an ISO as a hard disk causes Hyper-V to silently ignore it at boot — no error, but cloud-init never sees the `cidata` volume.

**Fix:** Use `dvd_drives` block for the seed ISO, not `hard_disk_drives`:
```hcl
dvd_drives {
  path                = "${var.seed_staging_windows_path}\\${each.key}-seed.iso"
  controller_number   = 0
  controller_location = 1   # location 0 = OS disk, location 1 = DVD
}
```

**Why silent:** Hyper-V does not error on attaching an ISO as a hard disk — it just fails to present the volume to the guest. Cloud-init waits for the `cidata` label and times out, falling back to DHCP.
