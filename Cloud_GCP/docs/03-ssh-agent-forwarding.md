# SSH Agent Forwarding — Jump Host Access on GCP

## Overview

This document covers how to securely access internal GCP VMs through a jump host using **SSH key-based authentication** and **agent forwarding** — the standard DevOps approach.

---

## Why Not `gcloud auth login` on the Jump Host?

The initial (wrong) approach was:

1. `gcloud compute ssh jump-host` — connect to the jump host
2. `gcloud auth login` on the jump host — authenticate Google account there
3. `gcloud compute ssh internal-vm --internal-ip` — connect to internal VMs

**Problem:** This stores your Google credentials on a machine exposed to the internet. If someone compromises the jump host, they have your authenticated gcloud session and can do anything your account can — create VMs, delete resources, access other projects.

**The correct approach:** SSH keys + agent forwarding. Your credentials never leave your laptop.

---

## Key Concepts

### SSH Key Pair

Two files that work together:

- **Private key** (`id_ed25519`) — stays on your laptop, never shared with anyone. This is your identity proof.
- **Public key** (`id_ed25519.pub`) — goes on every server you want to access. It's safe to share.

When you connect, the server checks: "does this person have the matching private key?" If yes — access granted. No passwords, no Google login needed on remote machines.

### ssh-agent

A small program that runs in the background on your local machine. It holds your private key in memory so you don't have to type the key's passphrase every time you connect.

Think of it as a keychain that keeps your keys ready to use.

- `eval $(ssh-agent -s)` — starts the agent. Returns a PID (Process ID) confirming it's running.
- `ssh-add ~/.ssh/id_ed25519` — loads your private key into the agent. Asks for the passphrase once.

**Important:** The agent only lives in the terminal window where you started it. If you close Git Bash and open a new one, you need to run these two commands again.

### Agent Forwarding (`-A` flag)

When you SSH to the jump host with `-A`, you're telling SSH: "let the jump host ask my local ssh-agent to authenticate on my behalf."

The private key **never leaves your laptop**. The jump host just passes the authentication request back to your machine through the SSH connection.

```
Your laptop (private key here, never leaves)
    │
    │  ssh -A jump-host   (agent forwarding)
    │
    ▼
jump-host (no credentials stored)
    │
    │  ssh internal-vm    (jump host asks YOUR laptop to authenticate)
    │
    ▼
internal-vm (connected — key was never on the jump host)
```

### Session

When you SSH into a server, that's a session — your active connection. When you type `exit` or close the terminal, the session ends. Agent forwarding only works during your active session — nothing is stored on the jump host permanently.

### GCP Project-Level SSH Keys

Instead of uploading your public key to each VM individually, GCP lets you add it once at the **project level**. Every VM in the project automatically accepts that key. One place to manage, all VMs get it.

### SSH Config File (`~/.ssh/config`)

SSH's configuration file. Instead of typing long commands with flags, IPs, and usernames every time, you define them once here. Every SSH client reads this file automatically.

### ProxyJump

A directive in the SSH config that tells SSH: "to reach this host, go through another host first." It automates the two-hop connection (laptop → jump host → internal VM) into one command.

The connection still goes through the jump host — ProxyJump doesn't skip it. It just automates the process. The firewall rules still enforce that internal VMs are only reachable through the jump host.

---

## Infrastructure (Created by Terraform)

| VM | IP | Access |
|---|---|---|
| jump-host | External: `34.116.244.13`, Internal: `10.0.1.4` | SSH from internet (port 22 only) |
| internal-vm-1 | Internal: `10.0.1.3` | SSH from jump host only |
| internal-vm-2 | Internal: `10.0.1.6` | SSH from jump host only |
| internal-vm-3 | Internal: `10.0.1.5` | SSH from jump host only |

Firewall rules:

- `allow-ssh-external` — internet → jump-host, port 22 only
- `allow-ssh-internal` — jump-host → internal VMs, port 22 only
- `allow-internal` — internal VMs talk to each other freely

---

## Setup Steps

All commands are run in **Git Bash** (not CMD — CMD doesn't have ssh-agent or agent forwarding support).

### Step 1: Generate SSH Key Pair

```bash
mkdir -p ~/.ssh
ssh-keygen -t ed25519 -C "penina-gcp"
```

| Flag | Meaning |
|---|---|
| `-t ed25519` | Key type. Ed25519 is modern, fast, more secure than older RSA |
| `-C "penina-gcp"` | A comment/label for the key. Just for identification, doesn't affect security |

When prompted:

- **File path** — press Enter for default (`~/.ssh/id_ed25519`)
- **Passphrase** — type a password to protect the key file. Characters won't be visible — that's normal

This creates two files:

- `~/.ssh/id_ed25519` — private key (on Windows: `C:\Users\ASUS\.ssh\id_ed25519`)
- `~/.ssh/id_ed25519.pub` — public key

### Step 2: Upload Public Key to GCP Project Metadata

```bash
echo "penina:$(cat ~/.ssh/id_ed25519.pub)" > /tmp/ssh-keys.txt
gcloud compute project-info add-metadata --metadata-from-file ssh-keys=/tmp/ssh-keys.txt
```

| Part | Meaning |
|---|---|
| `penina:` | Username that will be created on every VM automatically |
| `$(cat ~/.ssh/id_ed25519.pub)` | Reads the public key and inserts it into the command |
| `project-info add-metadata` | Adds the key at the project level — all VMs in the project accept it |

**What happens on GCP's side:** Every VM checks project metadata when someone tries to SSH in. If the presented key matches a key in the metadata — access granted, the specified user is created automatically.

### Step 3: Start SSH Agent and Load Key

```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
```

| Command | What it does |
|---|---|
| `eval $(ssh-agent -s)` | Starts the agent in the background. Returns `Agent pid NNN` |
| `ssh-add ~/.ssh/id_ed25519` | Loads the private key into the agent. Asks for passphrase once |

**Note:** The agent only exists in this terminal session. New Git Bash window = run these again.

### Step 4: Create SSH Config File

```bash
cat > ~/.ssh/config << 'EOF'
Host jump
    HostName 34.116.244.13
    User penina
    ForwardAgent yes

Host internal-1
    HostName 10.0.1.3
    User penina
    ProxyJump jump

Host internal-2
    HostName 10.0.1.6
    User penina
    ProxyJump jump

Host internal-3
    HostName 10.0.1.5
    User penina
    ProxyJump jump
EOF
```

| Directive | Meaning |
|---|---|
| `Host jump` | Nickname — you type `ssh jump` instead of the full command |
| `HostName` | Actual IP address |
| `User` | Login username |
| `ForwardAgent yes` | Same as `-A` flag, but always on for this host |
| `ProxyJump jump` | "To reach this host, go through `jump` first" |

**Important:** If the jump host IP changes (after `terraform destroy` and re-apply), update `HostName` in this file. GCP assigns a new external IP each time unless you reserve a static IP.

---

## How to Connect

### Quick Start (every time you open a new Git Bash)

```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
```

### Connect to Jump Host

```bash
ssh jump
```

### Connect Directly to Internal VMs (through jump host automatically)

```bash
ssh internal-1
ssh internal-2
ssh internal-3
```

SSH handles both hops transparently. You land on the internal VM. The connection still goes through the jump host — confirmed by `Last login: from 10.0.1.4` (the jump host's internal IP).

### Manual Two-Step Connection (same result, just more typing)

```bash
ssh -A penina@34.116.244.13         # Step 1: get to jump host
ssh penina@10.0.1.3                  # Step 2: from jump host to internal VM
```

### Verify Agent Forwarding is Active (from the jump host)

```bash
ssh-add -L
```

Shows your public key — proves the jump host can ask your laptop to authenticate. The private key is still only on your laptop.

---

## Security Summary

| Aspect | Before (wrong) | After (correct) |
|---|---|---|
| Credentials on jump host | Google account session | Nothing |
| What's exposed if jump host is hacked | Full GCP access | SSH session only (ends when you disconnect) |
| Authentication method | `gcloud auth login` | SSH key pair |
| Key location | N/A | Private key only on laptop |
| How internal VMs authenticate | gcloud on jump host | Agent forwarding from laptop |

---

## Troubleshooting

### "Permission denied (publickey)"

- SSH agent not running. Run `eval $(ssh-agent -s)` and `ssh-add ~/.ssh/id_ed25519`
- Public key not uploaded to GCP. Re-run the Step 2 metadata command
- Wrong username. Check that `User` in SSH config matches the username used when uploading the key

### Passphrase asked twice (once per hop)

- SSH agent died or wasn't started. Run `eval $(ssh-agent -s)` and `ssh-add` again

### "Host key verification failed"

- The VM was recreated (new `terraform apply`) and got a different host key
- Fix: `ssh-keygen -R <IP>` to remove the old fingerprint, then connect again

### Connection timeout to internal VMs

- Check firewall rules: `gcloud compute firewall-rules list`
- Verify the jump host has the `jump-host` tag and internal VMs have the `internal` tag
- Verify the internal VM IP hasn't changed: `terraform output`

---

## Files Created

| File | Location | Purpose |
|---|---|---|
| `id_ed25519` | `C:\Users\ASUS\.ssh\` | Private key — never share |
| `id_ed25519.pub` | `C:\Users\ASUS\.ssh\` | Public key — uploaded to GCP |
| `config` | `C:\Users\ASUS\.ssh\` | SSH host definitions |
| `known_hosts` | `C:\Users\ASUS\.ssh\` | Server fingerprints (auto-created on first connect) |
