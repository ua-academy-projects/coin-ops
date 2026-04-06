# Blockers and Workarounds

## 1) History service logs inserts but DB on VM5 looks empty
- **Common cause**: wrong runtime env (e.g., `DATABASE_URL` points elsewhere).
- **Workaround**:
  - Check effective env in service:
  - `systemctl show history_service --property=Environment`
  - Verify DB target from VM3:
  - `psql "host=10.10.1.6 ..."`
  - Capture traffic on all interfaces:
  - `sudo tcpdump -i any -nn port 5432`

## 2) RabbitMQ unreachable from Proxy/History service
- **Symptom**: publish/consume reconnect errors.
- **Workaround**:
  - Verify host/port: `nc -vz 10.10.1.5 5672`
  - Check broker user and vhost in `RABBITMQ_URL`
  - Ensure firewall allows AMQP between VM2/VM3 and broker VM.

## 3) PostgreSQL network access fails
- **Symptom**: connection refused / no pg_hba entry.
- **Workaround**:
  - In `postgresql.conf`: set `listen_addresses = '*'` (or private IP).
  - In `pg_hba.conf`: allow VM subnet `10.10.1.0/24`.
  - Reload PostgreSQL: `sudo systemctl reload postgresql`

## 4) systemd reads old env values
- **Symptom**: env file edited, behavior unchanged.
- **Workaround**:
  - `sudo systemctl daemon-reload`
  - `sudo systemctl restart <service>`
  - Validate with `systemctl show <service> --property=Environment`

## 5) Hardcoded Secrets in Environment Files
- **Symptom**: Storing plaintext passwords inside shared `.env` files is a security risk and breaks true IaC portability.
- **Workaround**:
  - Migrated configuration management to **Ansible Vault**.
  - Passwords (e.g., PostgreSQL, RabbitMQ) are encrypted in `vault.yml`.
  - Non-secret variables are kept in plaintext `vars.yml`.
  - Services use Jinja2 dynamically rendered templates (`.env.j2`) deployed with secure `0600` permissions on the guest VMs.
