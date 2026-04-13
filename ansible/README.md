# Ansible Deployment

Deploys all five coin-ops services to Vagrant VMs.

## Prerequisites

```bash
ansible-galaxy collection install \
  ansible.posix \
  community.general \
  community.postgresql \
  community.rabbitmq
```

## Required environment variables

Set these before running any playbook:

| Variable | Used by | Description |
|---|---|---|
| `DB_PASSWORD` | `db-server.yml`, `history-service.yml` | PostgreSQL `coinops` user password |
| `RABBIT_MQ_PASSWORD` | `msg-queue.yml`, `history-service.yml`, `api-proxy.yml` | RabbitMQ `coinops` user password |
| `HOST_IP` | `msg-queue.yml` | Your machine's LAN IP (CIDR, e.g. `192.168.0.10/32`) — grants access to the RabbitMQ management UI on port 15672 |

Example:

```bash
export DB_PASSWORD=mysecretdbpass
export RABBIT_MQ_PASSWORD=mysecretrabbitmqpass
export HOST_IP=192.168.0.10/32
```

If `HOST_IP` is not set, the management UI rule defaults to `127.0.0.1/32` (localhost only).

## Running

```bash
cd ansible

# Full deployment
ansible-playbook site.yml

# Single service
ansible-playbook playbooks/api-proxy.yml
```

## Notes

- SSH keys are read from `../vagrant/.vagrant/machines/<name>/vmware_desktop/private_key` — run `vagrant up` from `../vagrant/` first.
- Go binaries are compiled on the target VM; the playbook only recompiles when source files change (`sync_result.changed`).
- `go_arch` is detected automatically from `ansible_architecture` (`aarch64` → `arm64`, everything else → `amd64`).