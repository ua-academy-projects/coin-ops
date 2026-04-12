# Project Blockers & Infrastructure Issues

This document tracks technical hurdles encountered during infrastructure development and the migration to Docker.

## Phase 2: Docker Migration & Decoupling (Current)

### 1) Host Port Conflicts
- **Issue:** Ports `8080`, `6379`, and `5672` were already allocated on the host machine (by other Docker projects or local services).
- **Impact:** Docker Compose failed to start services.
- **Resolution:** 
  - Switched from `ports` to `expose` for internal services (`redis`, `rabbitmq`).

### 2) Binary Overwriting via Volumes (Go)
- **Issue:** Using Docker Bind Mounts (`volumes`) for the Go-based `proxy` service mapped the local Windows directory over the container's `/app` directory.
- **Impact:** The Linux-compiled `proxy.bin` inside the container was replaced/hidden by the host's directory content, causing `exec ./proxy.bin: no such file or directory`.
- **Resolution:** Removed the volume mount for the `proxy` service. Volumes are now strictly used for interpreted languages (Python) where live-coding is beneficial.

### 3) Hybrid Network Connectivity
- **Issue:** Docker containers (running via WSL2) needed to access the PostgreSQL database running on a separate Vagrant VM (`10.10.1.6`).
- **Impact:** Connection timeouts.
- **Resolution:** Configured PostgreSQL `pg_hba.conf` via Ansible to allow the Docker/WSL subnet and ensured `PGHOST` in `.env` points to the static VM IP.

### 4) Manual Environment Synchronization (Win -> WSL -> Containers)
- **Issue:** Manually maintaining `.env` files led to inconsistencies between the PostgreSQL password in the VM (managed by Ansible) and the application settings in Docker (managed manually).
- **Impact:** Failed database connections and authentication errors after VM password rotations.
- **Resolution:** Implemented **"Infrastructure-driven .env generation"**. Ansible (running inside the VM) now templates the `.env` file directly into the synced folder `/vagrant`. Docker in WSL immediately picks up the updated, vault-sourced variables. This ensures 100% consistency across the entire stack.

---

## Phase 1: Ansible & Vagrant (Legacy)

### 1) History service logs inserts but DB on VM5 looks empty
- **Common cause**: wrong runtime env (e.g., `DATABASE_URL` points elsewhere).
- **Workaround**:
  - Check effective env in service:
  - `systemctl show history_service --property=Environment`
  - Verify DB target from VM3:
  - `psql "host=10.10.1.6 ..."`
  - Capture traffic on all interfaces:
  - `sudo tcpdump -i any -nn port 5432`

### 2) RabbitMQ unreachable from Proxy/History service
- **Symptom**: publish/consume reconnect errors.
- **Workaround**:
  - Verify host/port: `nc -vz 10.10.1.5 5672`
  - Check broker user and vhost in `RABBITMQ_URL`
  - Ensure firewall allows AMQP between VM2/VM3 and broker VM.

### 3) PostgreSQL network access fails
- **Symptom**: connection refused / no pg_hba entry.
- **Workaround**:
  - In `postgresql.conf`: set `listen_addresses = '*'` (or private IP).
  - In `pg_hba.conf`: allow VM subnet `10.10.1.0/24`.
  - Reload PostgreSQL: `sudo systemctl reload postgresql`

### 4) systemd reads old env values
- **Symptom**: env file edited, behavior unchanged.
- **Workaround**:
  - `sudo systemctl daemon-reload`
  - `sudo systemctl restart <service>`
  - Validate with `systemctl show <service> --property=Environment`

### 5) Hardcoded Secrets in Environment Files
- **Symptom**: Storing plaintext passwords inside shared `.env` files is a security risk and breaks true IaC portability.
- **Workaround**:
  - Migrated configuration management to **Ansible Vault**.
  - Passwords (e.g., PostgreSQL, RabbitMQ) are encrypted in `vault.yml`.
  - Non-secret variables are kept in plaintext `vars.yml`.
  - Services use Jinja2 dynamically rendered templates (`.env.j2`) deployed with secure `0600` permissions on the guest VMs.

### 6) Vagrant SSH Authentication Failure on Initial Provisioning
- **Symptom**: `vagrant up` encounters `"Warning: Authentication failure. Retrying..."` timeouts and fails to execute the Ansible provisioner.
- **Root Cause**: The infrastructure enforces custom SSH keys (`.ssh/vagrant_key`). However, on a newly created VM prior to Ansible execution, the VM only accepts the default unsecure Vagrant key.
- **Workaround**:
  - Ensure `Vagrantfile` configures the SSH key path as an array with a fallback mechanism: `config.ssh.private_key_path = [".ssh/vagrant_key", "~/.vagrant.d/insecure_private_key"]`.
  - Validate that your custom key has been generated on the host machine (`ssh-keygen -t ed25519 -f .ssh/vagrant_key`).
  - Upon successful connection using the fallback key, Ansible will automatically inject the custom public key and revoke the insecure default key.

### 7) Ansible Vault Password File Missing
- **Symptom**: Execution of `vagrant up` or Ansible playbooks aborts with an error indicating failure to decrypt `vault.yml` or that `.vault_pass` is missing.
- **Root Cause**: The `.vault_pass` file contains sensitive decryption keys and is explicitly excluded via `.gitignore`.
- **Workaround**:
  - Request the current Vault password from the infrastructure maintainer.
  - Create a `.vault_pass` file in the project root directory containing the plaintext password string on a single line.

### 8) Service External DNS Resolution Failures
- **Symptom**: Services (especially the Proxy service) experience timeouts when attempting to reach external APIs (e.g., CoinGecko, NBU).
- **Root Cause**: The default local DNS resolver provided by hypervisors (VMware/VirtualBox) in NAT mode can sporadically hang, particularly after host hibernation or network state changes.
- **Workaround**:
  - A fallback mechanism is provisioned via systemd-resolved (`/etc/systemd/resolved.conf.d/99-coinops-dns.conf`) pointing to public DNS (`8.8.8.8`).
  - If the issue persists, manually flush and restart the resolver on the affected VM: `sudo systemctl restart systemd-resolved`.

### 9) `ansible_local` cannot find `/vagrant/infra/playbook.yml`
- **Symptom**: Provisioning fails with ``playbook does not exist on the guest: /vagrant/infra/playbook.yml``.
- **Root Cause**: Project root is not synced to `/vagrant` in guest VMs.
- **Workaround**:
  - Ensure synced folder is explicitly enabled per node:
  - `node.vm.synced_folder ".", "/vagrant"`
  - Keep services sync separately if needed (`services/` -> `/home/vagrant/shared_folder`).

### 10) RabbitMQ module/collection failures during provisioning
- **Symptom**: Errors like `couldn't resolve module/action 'rabbitmq_permissions'`.
- **Root Cause**: Missing `community.rabbitmq` collection and/or outdated short module names.
- **Workaround**:
  - Install collection before playbook run via `infra/requirements.yml` (`community.rabbitmq`).
  - Use fully qualified module names (for example, `community.rabbitmq.rabbitmq_user`).

### 11) Database init fails under `become_user: postgres`
- **Symptom A**: `chmod: invalid mode: 'A+user:postgres:rx:allow'` during Ansible temp file handling.
- **Root Cause A**: Missing `acl` package required for privilege escalation to unprivileged users.
- **Workaround A**:
  - Install `acl` in base packages on all VMs.
- **Symptom B**: `Permission denied` reading `/home/vagrant/shared_folder/database/*` as `postgres`.
- **Root Cause B**: Synced folder permissions allow `vagrant`, but `postgres` cannot read files directly.
- **Workaround B**:
  - Copy rendered init assets (for example `/tmp/init.sql`) to a location readable by `postgres`, run `psql`, then clean up temp files.

### 12) DB init uses wrong network settings from rendered DB env
- **Symptom**: `psql` fails with `connection refused` to VM IP during init.
- **Root Cause**: Exporting full rendered DB env injects `PGHOST/PGPORT/PGDATABASE`, forcing TCP connection instead of local postgres socket.
- **Workaround**:
  - Parse only app credentials (`PGUSER`, `PGPASSWORD`) needed for SQL variables.
  - Before `psql`, unset connection env vars:
  - `unset PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD`
  - Ensure PostgreSQL config handlers are applied before init (`meta: flush_handlers`).
