# Ansible Playbook & SSH Reference

## SSH Key Authentication

### How to connect

```powershell
ssh -i .\.vagrant\machines\node-1\hyperv\private_key vagrant@172.31.1.10
```

Vagrant generates a private key per VM and stores it at `.vagrant/machines/<node>/hyperv/private_key`.
The corresponding public key is injected into the VM during `vagrant up`, so password auth is not needed.

### Why you see "authenticity of host can't be established"

First time SSH connects to an IP it hasn't seen before. It shows the server's fingerprint and asks you to confirm.
Once you accept (`yes`), SSH adds the fingerprint to `~/.ssh/known_hosts` and never asks again for that IP.

### Why multiple IPs appear in known_hosts warnings

Every `vagrant destroy` + `vagrant up` cycle assigns the VM a new DHCP address on the external Hyper-V NIC,
but reuses the same private key. SSH sees the same key appearing at new IPs and warns you.

The internal network IP (`172.31.1.x`) is static — set in the Vagrantfile. The floating addresses in the warning
are from previous sessions on the dynamic NIC.

### Fix: clean up stale entries

```powershell
ssh-keygen -R 172.21.196.200
ssh-keygen -R 172.31.3.51
```

### Fix: suppress warnings for the private network

Add to `C:\Users\<you>\.ssh\config`:

```
Host 172.31.1.*
    StrictHostKeyChecking no
    UserKnownHostsFile NUL
```

Safe for local-only networks. Do not use this pattern for production hosts.

---

## Ansible Playbook Explained

### Structure

```
ansible/
├── inventory                  # who gets targeted (IPs + groups)
├── group_vars/all/
│   ├── main.yml               # non-secret variables (committed)
│   └── secrets.yml            # passwords (gitignored)
├── provision.yml              # run once: install system packages
├── deploy.yml                 # run every push: deploy services
└── roles/
    ├── proxy/                 # Go proxy service (node-02)
    ├── history/               # Python history service (node-01)
    └── ui/                    # nginx static files (node-03)
```

### inventory

Maps group names to IPs:

```ini
[history]
softserve-node-01 ansible_host=172.31.1.10

[proxy]
softserve-node-02 ansible_host=172.31.1.11

[ui]
softserve-node-03 ansible_host=172.31.1.12
```

When a playbook says `hosts: proxy`, Ansible SSHes into node-02 only.

### group_vars — variables

`main.yml` holds non-secret config. `secrets.yml` holds passwords (gitignored).
Ansible merges both — any task or template can use `{{ rabbitmq_password }}` and it resolves.

### provision.yml — run once

Sets up bare VMs. Safe to re-run (idempotent — checks before acting).

| Node | What gets installed |
|------|-------------------|
| history (node-01) | PostgreSQL, RabbitMQ, Python3 + venv |
| proxy (node-02) | golang-go |
| ui (node-03) | nginx |

Also creates the RabbitMQ user, PostgreSQL user and database.

```bash
ansible-playbook -i ansible/inventory ansible/provision.yml
```

### deploy.yml — run every push

Calls one role per host group:

```bash
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

#### Role: proxy (node-02)

```
1.  Create system user "cognitor-proxy" (no shell, no login)
2.  Create /etc/cognitor/ directory (secrets, mode 0750)
3.  Create /opt/cognitor/proxy/ directory
4.  rsync proxy/ source → /opt/cognitor/proxy/   (excludes compiled binaries)
5.  go mod download
6.  go build → /opt/cognitor/proxy/proxy          [notify: restart]
7.  Set binary permissions (owner: cognitor-proxy, mode 0750)
8.  Render proxy.env.j2 → /etc/cognitor/proxy.env [notify: restart]
9.  Render proxy.service.j2 → systemd unit        [notify: restart]
10. flush_handlers → restart runs NOW
11. systemd: enable + start cognitor-proxy
12. GET /health, retry 12×5s (60s timeout)
```

`proxy.env.j2` renders to:
```
RABBITMQ_URL=amqp://cognitor:<password>@172.31.1.10:5672/
PORT=8080
```

`proxy.service.j2` renders to a systemd unit that runs the binary as the unprivileged `cognitor-proxy` user
with `NoNewPrivileges=true` and `Restart=on-failure`.

#### Role: history (node-01)

Deploys two services: consumer (reads from RabbitMQ, writes to Postgres) and API (serves HTTP).

```
1-3. Create user, directories
4.   rsync history/ source
5.   Fix ownership recursively
6.   pip install requirements.txt into virtualenv
7.   Fix venv ownership
8.   Render history.env.j2                         [notify: restart both]
9.   Render history-consumer.service.j2            [notify: restart consumer]
10.  Render history-api.service.j2                 [notify: restart api]
11.  flush_handlers
12.  systemd: enable + start both services
13.  GET /health, retry 12×5s
```

#### Role: ui (node-03)

No compilation — just file copies and nginx config:

```
1. Create /var/www/coin-ops/
2. Copy index.html                                 [notify: reload nginx]
3. Copy nginx.conf → sites-available              [notify: reload nginx]
4. Symlink sites-available → sites-enabled        [notify: reload nginx]
5. Remove default nginx site                       [notify: reload nginx]
6. flush_handlers → nginx -s reload (graceful, no dropped connections)
7. systemd: ensure nginx is started
```

### Handlers

Handlers fire once per play, even if notified by multiple tasks. They run at `flush_handlers` or end of play.

```yaml
# proxy/handlers/main.yml
- name: Reload and restart proxy
  systemd:
    name: cognitor-proxy
    daemon_reload: yes   # re-reads .service file
    state: restarted
```

`daemon_reload: yes` is required whenever the `.service` file changes — otherwise systemd runs the old unit definition.

### Full deploy flow

```
your machine
    │
    ├─SSH→ node-02 (proxy)
    │      rsync .go source
    │      go build
    │      write proxy.env + proxy.service
    │      systemctl restart cognitor-proxy
    │      GET /health → 200 ✓
    │
    ├─SSH→ node-01 (history)
    │      rsync .py source
    │      pip install
    │      write history.env + service units
    │      systemctl restart consumer + api
    │      GET /health → 200 ✓
    │
    └─SSH→ node-03 (ui)
           copy index.html + nginx.conf
           nginx -s reload
```

Total time: ~2 minutes.
