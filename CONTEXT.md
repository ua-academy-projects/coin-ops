# CONTEXT.md — AI / maintainer context for **coin-ops**

**Purpose:** Ground truth for automated assistants and humans editing this repo. Load this file when working on `terraform/`, `ansible/`, deployments, or cross-service wiring.

**Project:** Polymarket dashboard (live markets, whale leaderboard, BTC/ETH/UAH pricing, historical charts). GCP is primary; AWS is secondary parity. Ansible today targets Hyper-V lab IPs (`172.31.1.x`); cloud migration is planned below.

---

## How to use this document (AI)

1. Prefer **minimal diffs**. Do not refactor unrelated paths.
2. Treat the **Do not change** section below as hard constraints unless the user explicitly overrides them with a justified design change.
3. **Generated / secret files:** never commit; see section 8 below.
4. **Jinja Compose files** under `deploy/compose/` are not valid raw Docker Compose; Ansible must template them first.
5. Canonical human docs also live under `docs/`, `CLAUDE.md`, `AGENTS.md`; this file compresses infra + guarded patterns for tooling.

---

## 1. Product and runtime topology (target cloud)

### Services

| Path | Stack | Responsibility |
|------|--------|----------------|
| `proxy/` | Go | Fetches external APIs (Polymarket Gamma/Data, CoinGecko, NBU); caches (Redis TTLs vary); publishes to broker; Redis session optional (503 if down) |
| `history/` | Python | `consumer.py` → DB; `main.py` → FastAPI (port 8000) |
| `ui-react/` | React + Vite | SPA with Recharts/Tailwind; prod build baked into nginx image |

### Data flow (after cloud layout)

```
Browser → nginx on app-1 (80/443)
       → /api/         → Go proxy on app-2 (:8080) → upstream APIs → queue → consumer → PostgreSQL
       → /history-api/ → FastAPI on app-2 (:8000) → PostgreSQL → browser
```

**Target VM roles:**

- **jump-host** — bastion + NAT only (iptables MASQUERADE); no app workloads.
- **app-1** — **UI only** (nginx gateway + static SPA). Public IP.
- **app-2** — **all backends**: proxy, history-api, history-consumer, PostgreSQL, RabbitMQ (when `RUNTIME_BACKEND=external`), Redis. Private subnet; egress via NAT.
- **db-1** — **remove from `terraform/config/config.json`**; replace later with RDS / CloudSQL (managed DB phase).

Example public IPs existed in workspace snapshots (do not rely on literals in CI): GCP jump-host / app-1 had public addresses; AWS same pattern.

### `RUNTIME_BACKEND`

- **`external`** — Redis + RabbitMQ as separate containers; classic path.
- **`postgres`** — queue/session patterns move into PostgreSQL via **pgmq** / extensions; compose uses custom image `deploy/postgres-runtime/Dockerfile` (pg_cron, pgmq). For `external`, Postgres image is typically `postgres:16-alpine`.

### Docker images (GHCR — **private**)

Deployments expect `docker login` via `GHCR_USERNAME` / `GHCR_TOKEN` (PAT with `read:packages`). Images under `ghcr.io/ua-academy-projects/` with tags like `shabat-latest`.

### API surface (history)

FastAPI exposes at least: `/health`, `/history`, `/history/{slug}`, `/prices/history/{coin}`. Proxy health is polled at `:8080/health`.

### Database idempotency

`consumer.py` uses **`ON CONFLICT DO NOTHING`** on unique keys (`slug, fetched_at` for markets; `coin, fetched_at` for prices). **Do not remove** — restarts replay safety.

---

## 2. Terraform architecture

### Providers and state

- `hashicorp/google` ~> 7.0, `hashicorp/aws` ~> 6.0, `hashicorp/local` ~> 2.0.
- Remote state (GCS): bucket `internship-state-bucket`, prefix `infra/state` (see `terraform/backend.tf`).

### JSON-driven config

Read from `terraform/config/*.json` via `jsondecode(file(...))` in `terraform/main.tf` locals. Key files:

| File | Role |
|------|------|
| `config.json` | `general` defaults + `instances` map (name → subnet, role, sizes, flags) |
| `networks.json` | `vpc_cidr`, `subnets`, `firewall_rules`, routing metadata |
| `mapping.json` | logical size labels → GCP/AWS machine types |
| `gcp.json` / `aws.json` | zone, image/AMI hints, optional `ssh_user` |
| `hosts.json` | **generated** by `terraform apply` — do not commit |
| `ssh_config` | **generated** — do not commit |

### Network model (VPC `10.10.0.0/16`)

- **external** subnet (`10.10.2.0/24`): public-facing; hosts jump-host + app-1.
- **internal** subnet (`10.10.1.0/24`): private; hosts app-2; default route via **NAT on jump-host** (GCP route + AWS private RT/route to jump ENI + `scripts/jump-host-init.sh`).

### Module map

- GCP: `gcp_network`, `gcp_firewall`, `gcp_instances`, `gcp_nat_route`.
- AWS: `aws_network`, `aws_security_groups`, `aws_instances`, `aws_nat_route`.
- Roots wire modules with `count = local.<cloud>_enabled ? 1 : 0`; `var.enabled_clouds` controls which stacks apply.

---

## 3. Critical pattern: instance config merge

In both `modules/gcp_instances/main.tf` and `modules/aws_instances/main.tf`, each VM config is merged in **fixed order** (later wins):

```text
merge(
  local.fallback,       # emergency defaults when upstream config is absent
  var.defaults,         # config.json → general
  var.cloud_defaults,   # gcp.json or aws.json
  cfg                     # config.json → instances → <vm_name>
)
```

Example (conceptual): `general.disk_size = 20` overrides `fallback.disk_size` when defaults are passed; per-instance keys override cloud defaults.

**This merge is foundational.** Do not “simplify” by flattening layers without explicit maintainer approval.

---

## 4. Do not change (without explicit approval)

| Item | Why |
|------|-----|
| **`local.fallback` blocks** in instance modules | Last-resort when variables/JSON are empty; production always overrides via merge. Removing/changing breaks isolated module tests and empty-input behavior. |
| **`local.fallback_sizes`** in instance modules | Intentional duplicate of `mapping.json` so the module still plans if `var.instance_sizes` is empty; removing yields opaque `Invalid index` errors. |
| **`jsonencode(jsondecode(...))` guard** for `source_instances` | Workaround for `any`-typed `var.instances` and Terraform type quirks; not a bug. |
| **`lifecycle { ignore_changes = [ami] }`** on `aws_instance` | Prevents mass replacement on every new Amazon-provided AMI build. |
| **`block-project-ssh-keys = "true"`** (GCP metadata) | Prevents silent injection of project-wide SSH keys; security posture. |
| **`source_dest_check = !can_ip_forward`** on AWS | Required for NAT/jump traffic; disabling `source_dest_check` for forwarders is mandatory for NAT-instance pattern. |
| **Jinja placeholders** in `deploy/compose/*.compose.yaml` | Must be rendered by Ansible `template:`; never `docker compose` these files raw. |
| **`ON CONFLICT DO NOTHING`** in consumer inserts | Replay-safe ingestion. |

---

## 5. Safe / intended changes (backlog highlights)

### Phase 1 Terraform fixes (still applicable if not merged)

1. **`aws_instances` fallback `disk_size`:** align `local.fallback.disk_size` **10 → 20** so behavior matches `config.json general` when `var.defaults` is omitted in tests-only runs.
2. **AWS private routing:** Private subnets should associate with a **private route table owned by `aws_network`** before NAT adds `0.0.0.0/0`; avoid two owners fighting `aws_route_table_association`. Desired shape: create empty private RT + associations in `aws_network`, pass `private_route_table_id` into `aws_nat_route`, which only adds the default route via jump ENI.

### Phase 2 — `jump-host-init.sh`

Hardcoded `10.10.1.0/24` in FORWARD rules should become **`${private_subnet_cidr}`** from `networks.json` via `templatefile()` (`.tpl`) and a variable plumbed from root module locals.

### Phases 3–4 — ops hardening

- Custom Linux user (e.g. `coinops`) + SSH key bootstrap (template script).
- Non-default SSH port only **after** login as the new user is verified; update `networks.json` rules and generated `ssh_config`.

### Phases 5–6 — Ansible inventory

- Add **GCP labels / AWS tags** (`role`, `project`, `cloud`) in Terraform for inventory plugins.
- Prefer **cloud inventory plugins** (`google.cloud.gcp_compute`, `amazon.aws.aws_ec2`) over “read `hosts.json` script” for true current state. Keep `hosts.json` for SSH config / human workflows, not as the sole inventory source.

### Phases 7+ — Ansible refactor for cloud

- Split static `ansible/inventory` (Hyper-V) into plugin-based inventory per cloud.
- **Debian vs Ubuntu:** GCP images are Debian; `roles/docker/` today assumes Ubuntu repos — must parameterize (`ansible_distribution | lower`).
- **New role shape:** `backend` on app-2 combining history + proxy stacks; `ui` on app-1; nginx `proxy_pass` targets **app-2 private IP** for `/api/` and `/history-api/`.
- Play order: bring **DB + broker** up before API health checks; UI last.

### DNS / TLS (later)

- Domain + Cloudflare NS; Terraform Cloudflare provider for A records to app-1 public IPs.
- Certbot staging → production; then `TLS_MODE=provided` in Ansible.

### Managed DB (future)

- **Cloud SQL:** private IP / Auth Proxy; no “open internet to Postgres”.
- **RDS:** private subnet groups, `deletion_protection`, final snapshots.
- Use **`terraform destroy -target`** lists that preserve DB modules when tearing down compute.

---

## 6. Ansible deployment (current vs target)

### Current layout (Hyper-V oriented)

- `ansible/inventory` — static `172.31.1.10/11/12`, user `vagrant`.
- `ansible/group_vars/all/main.yml` — embeds legacy LAN IPs for `postgres_bind_ip`, RabbitMQ URL, etc.
- Roles: `common`, `docker`, `history`, `proxy`, `ui`.
- Compose templates: `deploy/compose/node-01.compose.yaml` (history stack), `node-02` (proxy), `node-03` (ui).

### Environment contract (`.env` — not committed)

Playbooks assert `RABBITMQ_PASSWORD`, `DB_PASSWORD`, `SSH_KEY_PATH`, and `RUNTIME_BACKEND` in `{ '', external, postgres }`. Common additions: `APP_DOMAIN`, `TLS_MODE`, `IMAGE_TAG`, GHCR credentials, cloud credentials for dynamic inventory.

### Secrets on VMs

Ansible drops `/etc/cognitor/*.env`; compose files reference `env_file:` there.

---

## 7. Pitfalls (read before debugging)

### Terraform

- **`try(jsondecode(file(...)), {})`:** missing file becomes `{}` — mis-paths may silently “succeed” with fallbacks.
- **`module.foo[0]`** indexing: guard with `try` or `count`-aware expressions when cloud disabled.
- **`pathexpand`:** required for `~` in `ssh_public_key_path` on Windows-side workflows.
- **`local_file` hosts/ssh_config:** overwritten every apply.

### AWS

- One subnet ↔ one route table association; NAT refactors must not double-associate.
- AL2 AMI filters in `aws.json` are legacy; migrating AMI without `ignore_changes` can recreate instances.

### GCP

- `internal-vm` tag + `can_ip_forward` interact with NAT route targeting.
- Empty `access_config {}` grants ephemeral public IP; omit block for private NICs.

### Ansible / Compose

- Health task defaults: PostgreSQL readiness loops ~1 minute; failures are often resource/API timing, not app logic.
- `jump-host-init.sh` uses `iptables -C` before `-A` for idempotency; multi-NIC hops may need future hardening.

---

## 8. Never commit (examples)

```
terraform/config/hosts.json
terraform/config/ssh_config
terraform/sa-key.json
terraform/.terraform/
terraform/*.tfstate*
.env
```

---

## 9. Workstream checklist (ordered)

Use as a backlog index; execution state may drift — verify in git before claiming “done”.

1. Terraform Phase 1: `aws_instances` fallback disk; AWS private RT split / `aws_nat_route` consumes existing RT ID.
2. Template-driven NAT bootstrap CIDR.
3. Custom user + SSH workflow.
4. Non-default SSH port (after verified access).
5. VM labels/tags for inventory.
6. Cloud dynamic inventory plugins + credentials wiring.
7. Ansible topology refactor (app-1 UI, app-2 all backends); Debian Docker role.
8. `.env` + first cloud `provision.yml` / `deploy.yml`.
9. DNS (Terraform Cloudflare).
10. Certbot → `TLS_MODE=provided`.
11. RDS / CloudSQL + safe destroy-target patterns.

**Blockers:** domain propagation for TLS; managed DB naming retention (~30-day reuse lock on Cloud SQL names after delete).

---

## 10. Related repo docs

For narrative architecture and ops detail: `README.md`, `docs/architecture.md`, `docs/deployment.md`, `docs/terraform-guide.md`, `terraform/DEPLOY_TODO.md`, `CLAUDE.md`, `AGENTS.md`.
