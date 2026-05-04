# SSH Hardening — Custom Port & Operational User on GCP

## Mentor's Task

Two security improvements for the jump host infrastructure:

1. **Change default SSH port** — don't expose the well-known port 22. Use a custom port (9922) to eliminate automated bot attacks.
2. **Use a non-default operational user** — don't use `ubuntu` or any default system user. Create a dedicated operational user (`marta_ops`) defined as a Terraform variable, not hardcoded anywhere.

---

## Why Change Port 22?

Every server with port 22 open gets thousands of brute-force login attempts per day from automated bots. They scan every IP on the internet and try common passwords on port 22.

Changing to port 9922 makes the server invisible to those bots — they only check port 22. This is called "security through obscurity." It's not real security on its own (a determined attacker will port-scan and find it), but it's a good first layer that removes noise.

In production, you'd see hundreds of failed login attempts per hour on port 22 in your logs. Change the port — those attempts drop to near zero.

---

## Why a Non-Default User?

When GCP creates an Ubuntu VM, the default system user is `ubuntu`. Problems with using it:

- **Predictable** — attackers know every Ubuntu VM has a `ubuntu` user
- **Broad sudo permissions** — default user often has unrestricted sudo access
- **No accountability** — if everyone logs in as `ubuntu`, you can't track who did what
- **Hardcoded everywhere** — username appears in SSH configs, Ansible inventories, scripts

### The Operational User Approach

Instead of `ubuntu`, you create a dedicated user like `marta_ops`. The key principle: **the username is stored in a variable, not hardcoded**.

How it works across the stack:

| Tool | How it uses the variable |
|---|---|
| `terraform.tfvars` | `ops_user = "marta_ops"` — the single source of truth |
| `variables.tf` | `variable "ops_user"` — declares the variable, no default (forces explicit choice) |
| `main.tf` | `${var.ops_user}` — creates the user on each VM via SSH key metadata |
| `~/.ssh/config` | `User marta_ops` — local SSH config uses the same username |
| Ansible (future) | Reads the same variable to know which user to connect as |

If you need to change the username — you change it in **one place** (`terraform.tfvars`). Everything else references the variable.

In production, this value might live in a secrets manager (Vault, GCP Secret Manager) rather than a file — but the principle is the same: one source, many consumers.

---

## What Was Changed

### variables.tf — two new variables

```hcl
variable "ssh_port" {
  description = "SSH port for all VMs (non-default to reduce automated attacks)"
  type        = string
  default     = "9922"
}

variable "ops_user" {
  description = "Operational user for SSH access — used by Terraform, Ansible, and SSH config"
  type        = string
}
```

`ssh_port` has a default — the port is not a secret, and 9922 is a reasonable default.

`ops_user` has **no default** — Terraform forces you to set it in `terraform.tfvars`. This is intentional. The username is a conscious decision per project.

### terraform.tfvars — actual values

```hcl
ops_user = "marta_ops"
```

No `ssh_port` here because the default is fine. If another project needed port 8822, you'd add `ssh_port = "8822"` here to override.

### main.tf — firewall rules

Hardcoded `"22"` replaced with variable:

```hcl
# Before
ports = ["22"]

# After
ports = [var.ssh_port]
```

Both firewall rules (`allow_ssh_external` and `allow_ssh_internal`) now use the variable.

### main.tf — VM metadata

Added to both jump host and internal VMs:

```hcl
metadata = {
  ssh-keys = "${var.ops_user}:${file("~/.ssh/id_ed25519.pub")}"
}
```

This tells GCP: "create user `marta_ops` on this VM and authorize this SSH public key." GCP reads the `ssh-keys` metadata key and automatically creates the user with the provided public key.

`${var.ops_user}` pulls `marta_ops` from the variable. `${file("~/.ssh/id_ed25519.pub")}` reads the public key from the local machine at `terraform apply` time.

### main.tf — startup script

Added to both jump host and internal VMs:

```hcl
metadata_startup_script = <<-EOT
  #!/bin/bash
  if [ -f /etc/ssh/sshd_config.d/custom-port.conf ]; then
    echo "SSH already configured, skipping"
    exit 0
  fi
  cloud-init status --wait
  systemctl disable --now ssh.socket
  echo "Port ${var.ssh_port}" > /etc/ssh/sshd_config.d/custom-port.conf
  systemctl enable ssh.service
  systemctl restart ssh.service
EOT
```

Each line explained:

| Line | Purpose |
|---|---|
| `if [ -f ... ]; then exit 0; fi` | Idempotency guard — if config file exists, script already ran, skip everything |
| `cloud-init status --wait` | Wait until GCP's cloud-init finishes — prevents race conditions |
| `systemctl disable --now ssh.socket` | Disable Ubuntu 24.04's socket activation (see Problems below) |
| `echo "Port 9922" > .../custom-port.conf` | Write custom port to SSH drop-in config |
| `systemctl enable ssh.service` | Enable traditional SSH service |
| `systemctl restart ssh.service` | Restart SSH to apply the new port |

### Important: GCP Startup Script Types & Idempotency

**`metadata_startup_script` runs on EVERY boot** — not just the first one. If the VM reboots (update, crash, maintenance), the script runs again. This is a GCP design decision.

GCP metadata script types:

| Metadata key | When it runs |
|---|---|
| `startup-script` | Every boot |
| `shutdown-script` | Every shutdown |

There is no built-in "run once" key in GCP. To run something only on first boot, you have two options:

**Option 1: Idempotency guard (what we use)**

```bash
if [ -f /etc/ssh/sshd_config.d/custom-port.conf ]; then
  exit 0
fi
```

The script checks: "does my config file already exist?" If yes — the script already ran on first boot, nothing to do, exit immediately. First boot: runs fully. Every subsequent boot: exits in milliseconds.

**Option 2: cloud-init `user-data` with `runcmd`**

```hcl
metadata = {
  user-data = <<-EOT
    #cloud-config
    runcmd:
      - systemctl disable --now ssh.socket
      - echo "Port 9922" > /etc/ssh/sshd_config.d/custom-port.conf
      - systemctl enable ssh.service
      - systemctl restart ssh.service
  EOT
}
```

`runcmd` in cloud-config runs only on first boot by default. Cloud-init tracks what it already executed.

**Why idempotency matters:**

Without the guard, every reboot would: wait for cloud-init (unnecessary), disable socket (already disabled), overwrite config (same content), restart SSH (kicks anyone connected). The guard eliminates all unnecessary work.

Example of a **non-idempotent** mistake: `echo "key" >> authorized_keys` (append). On every reboot, a duplicate line is added. After 10 reboots — 10 duplicate lines. The `>>` append operator is dangerous in startup scripts without a guard.

**This is the same concept as Ansible's idempotency** — running something once or a hundred times gives the same result without side effects.

### outputs.tf — added port and user

```hcl
output "ssh_port" {
  value       = var.ssh_port
  description = "SSH port used by all VMs"
}

output "ops_user" {
  value       = var.ops_user
  description = "Operational user for SSH access"
}
```

After `terraform apply`, `terraform output` shows the port and username — useful when you come back in a week and forget what you used.

### ~/.ssh/config — updated with port and user

```
Host jump
    HostName 34.118.5.110
    User marta_ops
    Port 9922
    ForwardAgent yes

Host internal-1
    HostName 10.0.1.29
    User marta_ops
    Port 9922
    ProxyJump jump
```

Three changes from the original config: new IPs, `User marta_ops` instead of `penina`, `Port 9922` on every host.

---

## Problems Encountered & Solutions

### Problem 1: `sed` didn't change SSH port

**What happened:** First attempt used `sed` to edit `/etc/ssh/sshd_config`:

```bash
sed -i 's/^#Port 22/Port 9922/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 9922/' /etc/ssh/sshd_config
systemctl restart sshd
```

SSH stayed on port 22.

**Root cause:** Two issues. First, on Ubuntu 24.04, the SSH service is called `ssh`, not `sshd` — so `systemctl restart sshd` failed silently. Second, `sed` pattern matching can fail if the line format differs from expected.

**Fix:** Instead of editing the main config, write a drop-in config file:

```bash
echo "Port 9922" > /etc/ssh/sshd_config.d/custom-port.conf
```

Ubuntu 24.04 reads all `.conf` files from the `sshd_config.d/` directory and applies them. Cleaner and more reliable than editing the main file.

### Problem 2: SSH socket activation (Ubuntu 24.04)

**What happened:** Config file was correct (`Port 9922`), SSH was restarted, but it still listened on port 22.

**Root cause:** Ubuntu 24.04 introduced **socket activation** for SSH. Instead of `sshd` opening the port itself, `systemd` opens port 22 via `ssh.socket` and passes connections to `sshd`. The `sshd_config` port setting is ignored because systemd already controls the port.

This is a breaking change from older Ubuntu versions where `sshd_config` was the only source of truth for the SSH port.

**Fix attempt 1 — override the socket:**

```bash
mkdir -p /etc/systemd/system/ssh.socket.d
echo "[Socket]" > override.conf
echo "ListenStream=" >> override.conf
echo "ListenStream=9922" >> override.conf
systemctl daemon-reload
systemctl restart ssh.socket
```

This failed due to a race condition with cloud-init (see Problem 3).

**Fix attempt 2 — disable socket activation entirely:**

```bash
systemctl disable --now ssh.socket
systemctl enable ssh.service
systemctl restart ssh.service
```

This disables the new socket mechanism and runs SSH the traditional way — where it reads `sshd_config` and opens the port itself. This worked.

### Problem 3: Race condition with cloud-init

**What happened:** The startup script ran, changed the socket config, restarted SSH — but cloud-init was running at the same time and restarted `ssh.socket` back to defaults. Our changes were overwritten.

**Root cause:** GCP runs the startup script and cloud-init concurrently. Both try to configure SSH, and the last one to run wins. The serial console showed:

```
ssh.socket: Socket unit configuration has changed while unit has been running
```

**Fix:** Added `cloud-init status --wait` as the first line of the startup script. This pauses execution until cloud-init is completely finished. No more race condition.

### Problem 4: `systemctl start` vs `systemctl restart`

**What happened:** Script wrote the port config and ran `systemctl start ssh.service`, but SSH stayed on port 22.

**Root cause:** SSH was already running (started by cloud-init on port 22). `start` does nothing if the service is already active. It doesn't re-read config files.

**Fix:** Changed `start` to `restart`. `restart` stops the service and starts it again, forcing it to re-read the config with the new port.

### Problem 5: Nested heredoc in Terraform

**What happened:** Tried to use a heredoc inside a heredoc (`<<-EOT` containing `<<INNER`). Terraform threw "Unterminated template string" error.

**Root cause:** Terraform's HCL parser doesn't support nested heredocs.

**Fix:** Replaced the inner heredoc with multiple `echo` commands:

```bash
echo "[Socket]" > override.conf
echo "ListenStream=" >> override.conf
echo "ListenStream=9922" >> override.conf
```

`>` overwrites the file, `>>` appends.

---

## How to Connect Now

### Every new Git Bash session — start the agent

```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
```

The agent only lives in the current terminal window. New window = run these again.

### Connect to any VM

```bash
ssh jump          # → jump host directly
ssh internal-1    # → internal-vm-1 through jump host
ssh internal-2    # → internal-vm-2 through jump host
ssh internal-3    # → internal-vm-3 through jump host
```

The SSH config handles everything: port 9922, user `marta_ops`, agent forwarding, ProxyJump through the jump host. One command, straight to any VM.

### Verify the setup

```bash
# Check what port SSH is listening on (from inside any VM)
sudo ss -tlnp | grep ssh

# Check the port config
cat /etc/ssh/sshd_config.d/custom-port.conf

# Check that socket activation is disabled
sudo systemctl status ssh.socket

# Check that SSH service is running
sudo systemctl status ssh.service
```

---

## Current Infrastructure State

| VM | External IP | Internal IP | Port | User |
|---|---|---|---|---|
| jump-host | 34.116.244.13 | 10.0.1.31 | 9922 | marta_ops |
| internal-vm-1 | — | 10.0.1.33 | 9922 | marta_ops |
| internal-vm-2 | — | 10.0.1.32 | 9922 | marta_ops |
| internal-vm-3 | — | 10.0.1.34 | 9922 | marta_ops |

---

## Key DevOps Lessons

1. **Ubuntu 24.04 SSH socket activation** — a real-world breaking change that many DevOps engineers encounter. The fix (disabling socket activation) is documented across the community.

2. **Race conditions in startup scripts** — cloud providers run multiple init systems concurrently. Always wait for dependencies (`cloud-init status --wait`) before making changes.

3. **`start` vs `restart`** — `start` is a no-op if the service is already running. `restart` forces a config reload. Know the difference.

4. **Variables over hardcoding** — the username and port live in `terraform.tfvars`. Every other file references variables. Changing a value means editing one file, not twenty.

5. **Debug with serial console** — when SSH is broken and you can't get in, `gcloud compute instances get-serial-port-output` shows the boot log. This is how you debug without SSH access.

6. **Keep a fallback port during testing** — temporarily opening port 22 alongside 9922 in the firewall lets you debug if the new port doesn't work. Remove it after confirming.

7. **Startup scripts run on every boot** — GCP's `metadata_startup_script` is not a "run once" mechanism. Always add an idempotency guard (`if file exists, exit`) or use cloud-init `runcmd` for one-time setup. Without this, scripts may cause unnecessary restarts, duplicate entries, or connection disruptions on every reboot.
