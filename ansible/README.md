# Ansible Deployment

This directory contains the provisioning and deployment logic for the project.

## Responsibility

- configures all Vagrant VMs
- installs packages
- renders systemd unit files
- creates PostgreSQL and RabbitMQ application users
- configures Redis networking
- starts all services

## Entry Points

- inventory: `inventory.ini`
- playbook: `site.yml`
- config: `../ansible.cfg`

## Inventory Groups

- `ui`
- `proxy`
- `history`
- `data`

Group `all` is also available implicitly and is used for shared variables.

## Variable Layout

Recommended structure:

```text
ansible/group_vars/all/main.yml
ansible/group_vars/all/vault.yml
```

`main.yml`:

- non-secret shared variables
- IP addresses
- ports
- usernames
- queue name
- database/table names

`vault.yml`:

- `postgres_password`
- `rabbitmq_password`
- `ui_secret_key`

## Why `main.yml` Works

Inside `group_vars/all/`, Ansible loads all YAML variable files for the `all` group. That means these filenames all work:

- `main.yml`
- `all.yml`
- `base.yml`
- `vault.yml`

What matters is the directory:

```text
group_vars/all/
```

## Playbook Layout

`site.yml` applies roles in this order:

1. `common` to all hosts
2. `postgres`, `rabbitmq`, `redis` to `data`
3. `history` to `history`
4. `proxy` to `proxy`
5. `ui` to `ui`

## Commands

Run full deployment:

```bash
ansible-playbook ansible/site.yml --ask-vault-pass
```

Run one host group:

```bash
ansible-playbook ansible/site.yml --limit ui --ask-vault-pass
ansible-playbook ansible/site.yml --limit proxy --ask-vault-pass
ansible-playbook ansible/site.yml --limit history --ask-vault-pass
ansible-playbook ansible/site.yml --limit data --ask-vault-pass
```

## Vault

To inspect encrypted variables:

```bash
ansible-vault view ansible/group_vars/all/vault.yml
```

If you get decryption errors, the usual causes are:

- wrong vault password
- wrong file location
- wrong encrypted file

## SSH Notes

`ansible.cfg` contains:

```ini
host_key_checking = False
```

This disables SSH host key verification, which is convenient for frequently recreated Vagrant VMs.

## Troubleshooting

### Variable is undefined

If a variable such as `postgres_password` is undefined, first check that the file is in:

```text
ansible/group_vars/all/vault.yml
```

and not in:

```text
ansible/group_vars/vault.yml
```

### Service file changed but systemd still uses old values

Check that:

- the template task ran
- handler performed `daemon-reload`
- the service was restarted

Useful commands:

```bash
sudo systemctl cat ui.service
sudo systemctl cat proxy.service
sudo systemctl cat history.service
```
