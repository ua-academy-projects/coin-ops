# Terraform — Розгортання VM

Розгортає 3 KVM/libvirt VM через `terraform-provider-libvirt`.

## Що створюється

| Ресурс | IP | RAM | Диск |
|---|---|---|---|
| VM1 `monero-frontend` | 10.10.10.11 | 128 МБ | 1 ГБ |
| VM2 `monero-backend` | 10.10.10.12 | 256 МБ | 1 ГБ |
| VM3 `monero-database` | 10.10.10.13 | 256 МБ | 1 ГБ |
| Мережа NAT `monero-net` | 10.10.10.0/24 | — | — |

## Передумови

```bash
# На хост-машині (Linux)
sudo apt install qemu-kvm libvirt-daemon-system
# або на Alpine: apk add qemu libvirt

# Terraform provider
terraform init
```

Завантажити Alpine cloud image:
```bash
wget https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/cloud/alpine-virt-3.19.1-x86_64.qcow2 \
  -O /var/lib/libvirt/images/alpine-virt-3.19.1-x86_64.qcow2
```

## Швидкий старт

```bash
cd terraform/

# 1. Скопіювати і заповнити змінні
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars        # вписати ssh_public_key, db_password, repo URL

# 2. Ініціалізація
terraform init

# 3. Перевірка плану
terraform plan

# 4. Розгортання (~2-3 хвилини)
terraform apply

# 5. Перегляд outputs
terraform output
```

## Після розгортання

```
frontend_url  = http://10.10.10.11        ← React дашборд
api_url       = http://10.10.10.12:8000   ← FastAPI
api_docs_url  = http://10.10.10.12:8000/docs
```

Cloud-init автоматично:
- встановлює всі залежності
- клонує репозиторій
- збирає React і деплоїть через nginx
- запускає FastAPI і Worker як OpenRC сервіси
- ініціалізує PostgreSQL з правильними правами

Автодеплой: cron щохвилини перевіряє нові коміти в git і перезапускає сервіси.

## Знищення

```bash
terraform destroy
```

## Типові проблеми

**`permission denied` для libvirt** — додай свого користувача до групи:
```bash
sudo usermod -aG libvirt $USER && newgrp libvirt
```

**VM не отримує IP** — перевір що `libvirtd` запущено:
```bash
sudo rc-service libvirtd start   # Alpine
sudo systemctl start libvirtd    # Ubuntu/Debian
```

**Backend не підключається до DB** — VM3 стартує повільніше. VM2 робить паузу 30с перед першим деплоєм. Можна вручну:
```bash
ssh deploy@10.10.10.12 /opt/monero-scripts/deploy.sh
```
