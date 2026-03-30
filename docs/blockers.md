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

## 5. Go build fails without network access during `go mod download`

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
