# Blockers and Workarounds

## 1) Worker logs inserts but DB on VM5 looks empty
- **Common cause**: wrong runtime env (e.g., `DATABASE_URL` points elsewhere).
- **Workaround**:
  - Check effective env in service:
  - `systemctl show worker --property=Environment`
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
