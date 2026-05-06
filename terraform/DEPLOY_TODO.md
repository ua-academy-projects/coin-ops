# GCP Cloud Deployment - TODO

Робочий чекліст для підняття coin-ops у GCP на базі `terraform-new` з JSON-driven конфігом і fallback-механікою.

Статуси:
- `[x]` виконано
- `[~]` в процесі / частково
- `[ ]` не виконано

## Топологія (цільова)

- `jump-host` (external, public IP): bastion + NAT для internal VM
- `app-1` (external, public IP): UI (`nginx`) + proxy
- `app-2` (internal): history API + consumer
- `db-1` (internal): PostgreSQL (режим `postgres`, з `pgmq`/`pg_cron`)

## Фаза 0 - Блокери Terraform

- `[x]` Додано shared SSH key для обох хмар через `var.ssh_public_key_path` у `terraform-new/variables.tf`.
- `[x]` Додано GCP metadata SSH key у `terraform-new/modules/gcp_instances/main.tf` з user із JSON (`gcp.json.ssh_user`).
- `[x]` Додано `can_ip_forward` + `startup_script` у `terraform-new/modules/gcp_instances/main.tf`.
- `[x]` Додано автотег `internal-vm` для VM без public IP у `terraform-new/modules/gcp_instances/main.tf`.
- `[x]` Додано NAT startup script: `terraform-new/scripts/jump-host-init.sh`.
- `[x]` Додано `local` provider у `terraform-new/providers.tf`.
- `[x]` Додано генерацію `hosts.json` через `local_file` у `terraform-new/main.tf`.
- `[x]` Додано fallback-safe логіку для умовних об'єктів через `jsonencode/jsondecode` у:
  - `terraform-new/modules/gcp_firewall/main.tf`
  - `terraform-new/modules/aws_security_groups/main.tf`
  - `terraform-new/modules/gcp_instances/main.tf`
  - `terraform-new/modules/aws_instances/main.tf`
- `[~]` NAT route (`google_compute_route.nat_route`) допрацьована на `next_hop_ip`, але треба завершити стабілізацію apply:
  - зараз були помилки індексації `instance_ips["jump-host"]` коли спрацьовував fallback `default-vm`.
  - потрібно довести до ідемпотентного стану (`terraform apply` двічі поспіль без змін).

## Фаза 1 - JSON-конфіг топології

- `[x]` Оновлено `terraform-new/config/config.json` під 4 VM (jump-host, app-1, app-2, db-1).
- `[x]` Оновлено `terraform-new/config/mapping.json` на логічну шкалу:
  - `micro -> e2-micro` / `t3.micro`
  - `small -> e2-small` / `t3.small`
  - `medium -> e2-standard-2` / `m7i-flex.large`
  - `large -> e2-standard-4` / `c7i-flex.large`
- `[x]` Оновлено `terraform-new/config/networks.json` під потрібні firewall rules.
- `[x]` Додано `ssh_user` у:
  - `terraform-new/config/gcp.json` (`debian`)
  - `terraform-new/config/aws.json` (`ec2-user`)
- `[x]` Оновлено `.gitignore` для `terraform-new/config/hosts.json` та terraform-new артефактів.

## Фаза 2 - Перевірка інфраструктури після apply

- `[x]` Базовий `terraform apply` виконувався, VM створені (за логом термінала).
- `[ ]` Повторний `terraform apply` має пройти без помилок (ідемпотентність).
- `[ ]` Підтвердити, що `config/hosts.json` реально створюється після успішного apply.
- `[ ]` Перевірити NAT з internal VM:
  - `ip_forward=1` на jump-host
  - `iptables MASQUERADE` активний
  - `curl`/`apt update` з `app-2` і `db-1` працюють

## Фаза 3 - Ansible bootstrap (через jump-host)

- `[ ]` Встановити Ansible на jump-host.
- `[ ]` Додати dynamic inventory script, що читає `terraform-new/config/hosts.json`.
- `[ ]` Запустити `ansible/provision.yml`.
- `[ ]` Запустити `ansible/deploy.yml`.
- `[ ]` Перевірити health endpoints:
  - UI health через `app-1`
  - proxy health
  - history API health

## Фаза 4 - DNS і TLS

- `[ ]` Домен (`nic.ua`) + Cloudflare (NS delegation).
- `[ ]` A-records через Terraform Cloudflare provider (на основі outputs/hosts.json).
- `[ ]` Certbot staging на app-VM.
- `[ ]` Після успіху - прод endpoint Let's Encrypt.
- `[ ]` Перехід на `TLS_MODE=provided`.

## Фаза 5 - Покращення (backlog)

- `[ ]` Перехід з metadata SSH keys на IAM/OS Login.
- `[ ]` Load Balancer перед app layer (для повністю private app VM).
- `[ ]` PostgreSQL backups (Cloud Storage).
- `[ ]` Секрети у Secret Manager.
- `[ ]` CI/CD пайплайн для деплою (GitHub Actions + Ansible run).

## Найближчі кроки (рекомендовано зараз)

1. Довести `terraform apply` до стабільного стану для `nat_route`.
2. Підтвердити генерацію `config/hosts.json`.
3. Почати Фазу 3: dynamic inventory + запуск Ansible з jump-host.
