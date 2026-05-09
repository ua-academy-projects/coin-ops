# CONTEXT.md — AI / maintainer context for **coin-ops**

**Purpose:** Ground truth for automated assistants and humans editing this repo. Load this file when working on `terraform/`, `ansible/`, deployments, or cross-service wiring.

**Project:** Polymarket dashboard (live markets, whale leaderboard, BTC/ETH/UAH pricing, historical charts). GCP is primary; AWS is secondary parity. The repository now runs on the cloud-first topology below; Hyper-V-era assumptions should be treated as legacy unless explicitly called out.

---

## How to use this document (AI)

1. Prefer **minimal diffs**. Do not refactor unrelated paths.
2. Treat the **Do not change** section below as hard constraints unless the user explicitly overrides them with a justified design change.
3. **Generated / secret files:** never commit; see section 8 below.
4. **Jinja Compose files** under `deploy/compose/` are not valid raw Docker Compose; Ansible must template them first.
5. Canonical human docs also live under `docs/`, `CLAUDE.md`, `AGENTS.md`; this file compresses infra + guarded patterns for tooling.

---

## 1. Product and runtime topology (current cloud target)

### Services

| Path | Stack | Responsibility |
|------|--------|----------------|
| `proxy/` | Go | Fetches external APIs (Polymarket Gamma/Data, CoinGecko, NBU); caches (Redis TTLs vary); publishes to broker; Redis session optional (503 if down) |
| `history/` | Python | `consumer.py` → DB; `main.py` → FastAPI (port 8000) |
| `ui-react/` | React + Vite | SPA with Recharts/Tailwind; prod build baked into nginx image |

### Data flow (after cloud layout)

```
Browser → Cloudflare proxy → nginx on app-1 (443)
       → /api/         → Go proxy on app-2 (:8080) → upstream APIs → queue → consumer → PostgreSQL
       → /history-api/ → FastAPI on app-2 (:8000) → PostgreSQL → browser
```

**Target VM roles:**

- **jump-host** — bastion + NAT only (iptables MASQUERADE); no app workloads.
- **app-1** — **UI only** (nginx gateway + static SPA). Public IP, but public HTTP ingress is intentionally closed; Cloudflare proxy fronts HTTPS.
- **app-2** — **all backends**: proxy, history-api, history-consumer, RabbitMQ (when `RUNTIME_BACKEND=external`), Redis, and local PostgreSQL only when not using a managed DB. Private subnet; egress via NAT.
- **Managed DB** — Cloud SQL is the current GCP managed-database path. There is no longer a separate `db-1` VM in the intended topology.

Example public IPs existed in workspace snapshots (do not rely on literals in CI): GCP jump-host / app-1 had public addresses; AWS same pattern.

### `RUNTIME_BACKEND`

- **`external`** — Redis + RabbitMQ as separate containers; classic path.
- **`postgres`** — queue/session patterns move into PostgreSQL via **pgmq** / extensions; compose uses custom image `deploy/postgres-runtime/Dockerfile` (pg_cron, pgmq). For `external`, Postgres image is typically `postgres:16-alpine`.

**Important guard:** `use_managed_db=true` with `RUNTIME_BACKEND=postgres` is intentionally unsupported and should fail early in Ansible.

### Docker images (GHCR)

Deployments support `docker login` via `GHCR_USERNAME` / `GHCR_TOKEN` (PAT with `read:packages`). Images under `ghcr.io/ua-academy-projects/` with tags like `shabat-latest`. If images are public, registry login is skipped cleanly.

### API surface (history)

FastAPI exposes at least: `/health`, `/history`, `/history/{slug}`, `/prices/history/{coin}`. Proxy health is polled at `:8080/health`.

### Database idempotency

`consumer.py` uses **`ON CONFLICT DO NOTHING`** on unique keys (`slug, fetched_at` for markets; `coin, fetched_at` for prices). **Do not remove** — restarts replay safety.

---

## 2. Terraform architecture

### Providers and state

- `hashicorp/google` ~> 7.0, `hashicorp/aws` ~> 6.0, `hashicorp/local` ~> 2.0.
- Remote state (GCS): bucket `internship-state-bucket`, prefix `infra/state` (see `terraform/backend.tf`).
- `terraform/bootstrap-gcp.sh` is the operator bootstrap entrypoint for the GCP-first workflow.

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
| `ansible-runtime.json` | **generated** narrow Terraform→Ansible metadata (managed DB/backend IPs) — do not commit |

### Bootstrap-generated local operator files

The normal workflow does **not** rely on a committed repo `.env`. Instead, bootstrap generates local gitignored operator files:

- `terraform/sa-key.json`
- `terraform/local.generated.auto.tfvars.json`
- `terraform/bootstrap.secrets.auto.tfvars`
- `ansible/vars/local.generated.json`
- `local/generated-env.sh`

`local/generated-env.sh` is the intended shell entrypoint before normal Terraform or Ansible work.

### Network model (VPC `10.10.0.0/16`)

- **external** subnet (`10.10.2.0/24`): public-facing; hosts jump-host + app-1.
- **internal** subnet (`10.10.1.0/24`): private; hosts app-2; default route via **NAT on jump-host** (GCP route + AWS private RT/route to jump ENI + `scripts/jump-host-init.sh`).

### Current public ingress policy

- Public SSH is allowed only to **jump-host** on the custom SSH port.
- Public HTTPS (`443`) is allowed to **app-1**.
- Public HTTP (`80`) is intentionally closed at the infrastructure layer.
- `app-1` reaches `app-2` on `8000` and `8080`.

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

## 5. Completed Architecture Shifts

- **Terraform enhancements:** AWS private routing split, dynamic `jump-host-init.sh`, custom user + SSH workflow, non-default SSH port, VM labels/tags for inventory, generated SSH config, and generated Ansible runtime metadata.
- **Ansible Dynamic Inventory:** Shifted away from `hosts.json` as inventory truth and now uses `google.cloud.gcp_compute` and `amazon.aws.aws_ec2`. Private hosts are reached through generated SSH config + `ProxyJump`.
- **Variables contract:** Repo `.env` is no longer the normal operator path. Bootstrap now generates local non-secret config and a generated local env file. Secrets are seeded once and then fetched from GCP Secret Manager during deploy.
- **Topology:** `app-1` is the UI gateway on public HTTPS; `app-2` runs all backend services on private IPs. Nginx `proxy_pass` targets `app-2` private IP for `/api/` and `/history-api/`.
- **DNS & TLS:** Terraform manages Cloudflare DNS records, currently intended to be proxied through Cloudflare. Ansible provisions Certbot DNS-challenge TLS on the origin.
- **Managed DB:** Cloud SQL is integrated via Terraform. Ansible uses generated runtime metadata to decide whether to target managed DB or local Postgres.
- **Safety:** Secret Manager secret containers and Cloud SQL resources are protected from casual `terraform destroy` by hard Terraform guards.

---

## 6. Ansible deployment (current contract)

### Current layout
- **Inventory:** Dynamic plugins (`inventory.gcp_compute.yml`, `inventory.aws_ec2.yml`).
- **Variables:** Stable non-secret defaults live in `ansible/vars/deploy-config.yml`, local operator overrides live in `ansible/vars/local.generated.json`, and dynamic connection/runtime values are resolved in `inventory/group_vars/all/main.yml`.
- **Roles:** `common`, `docker`, `history`, `proxy`, `ui`.
- **Play order:** Provision common/docker first, then backend services on `app-2`, then UI on `app-1`.

### Secret and config contract

- **Secrets:** GCP deployments fetch `DB_PASSWORD`, `RABBITMQ_PASSWORD`, `GHCR_TOKEN`, and `CLOUDFLARE_API_TOKEN` from GCP Secret Manager at deploy time.
- **Non-secrets:** `app_domain`, `tls_mode`, image defaults, ports, and similar values come from committed defaults plus generated local non-secret config.
- **Local shell state:** Operators should source `local/generated-env.sh` instead of `source .env`.

### Secrets on VMs

The current goal is to avoid persisting repo-managed runtime env files on the VMs. Compose templates should prefer direct `environment:` injection from Ansible-rendered values rather than long-lived `/etc/cognitor/*.env` files for application containers.

---

## 7. Pitfalls (read before debugging)

### Terraform

- **`try(jsondecode(file(...)), {})`:** missing file becomes `{}` — mis-paths may silently “succeed” with fallbacks.
- **`module.foo[0]`** indexing: guard with `try` or `count`-aware expressions when cloud disabled.
- **`pathexpand`:** required for `~` in `ssh_public_key_path` on Windows-side workflows.
- **`local_file` hosts/ssh_config:** overwritten every apply.
- **Cloudflare provider:** initialized even when DNS records are disabled; provider config uses a placeholder token fallback so init/plan still succeed without live DNS credentials.
- **Stateful destroy protection:** `prevent_destroy` is hardcoded on important GCP stateful resources; a real full teardown requires a deliberate temporary code edit (see `runbook.md`).

### AWS

- One subnet ↔ one route table association; NAT refactors must not double-associate.
- AL2 AMI filters in `aws.json` are legacy; migrating AMI without `ignore_changes` can recreate instances.

### GCP

- `internal-vm` tag + `can_ip_forward` interact with NAT route targeting.
- Empty `access_config {}` grants ephemeral public IP; omit block for private NICs.
- `google.cloud.gcp_compute` inventory works best with `auth_kind: application` plus `GOOGLE_APPLICATION_CREDENTIALS`.

### Ansible / Compose

- Health task defaults: PostgreSQL readiness loops ~1 minute; failures are often resource/API timing, not app logic.
- `jump-host-init.sh` uses `iptables -C` before `-A` for idempotency; multi-NIC hops may need future hardening.
- `inventory/group_vars/all/main.yml` intentionally loads local generated config and generated Terraform runtime metadata; do not revert to using `terraform/config/hosts.json` as inventory truth.
- `tls_mode=certbot` requires a real public domain and a valid Cloudflare token.

---

## 8. Never commit (examples)

```
terraform/config/hosts.json
terraform/config/ssh_config
terraform/config/ansible-runtime.json
terraform/sa-key.json
terraform/.terraform/
terraform/*.tfstate*
terraform/local.generated.auto.tfvars.json
terraform/bootstrap.secrets.auto.tfvars
ansible/vars/local.generated.json
local/generated-env.sh
.env
```

---

## 9. Current goals and next workstream

The current GCP-first refactor is implemented. The next work should focus on polish and cloud-native maturity, not reintroducing old workflows:

1. **Keep the generated bootstrap workflow stable:**
   - `bootstrap-gcp.sh` + generated local files are now the expected operator path.
   - Do not reintroduce repo `.env` as the primary workflow.
2. **Refine inventory/config separation further:**
   - Keep `group_vars` small and policy-oriented.
   - Move only truly inventory-native derivation into plugin `compose` or follow-up constructed inventory.
3. **Improve full-destroy ergonomics:**
   - The current hard-guard model is safe but manual for complete teardown.
   - A future improvement could isolate protected resources into separate state or a cleaner dedicated lifecycle.
4. **Managed services roadmap:**
   - AWS Secrets Manager parity is still pending.
   - Managed RabbitMQ/Redis equivalents remain future work.
5. **Image/provisioning optimization:**
   - Golden images or Packer remain good future work to shorten provisioning time.

---

## 10. Related repo docs

For narrative architecture and ops detail: `README.md`, `docs/architecture.md`, `docs/deployment.md`, `docs/terraform-guide.md`, `runbook.md`, `CLAUDE.md`, `AGENTS.md`.
