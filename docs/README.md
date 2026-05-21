# Documentation Index

## Architecture
- [overview.md](architecture/overview.md) — current deployed path vs PostgreSQL runtime target
- [runtime-queue.md](architecture/runtime-queue.md) — queue-side PostgreSQL runtime design
- [runtime.md](architecture/runtime.md) — runtime queue/cache user guide
- [adr/0001-postgres-runtime.md](architecture/adr/0001-postgres-runtime.md) — decision record

## Infrastructure
- [terraform-guide.md](infrastructure/terraform-guide.md) — Terraform conventions
- [infrastructure-guide.md](infrastructure/infrastructure-guide.md) — GCP infrastructure overview
- [gcp-deployment.md](infrastructure/gcp-deployment.md) — GCP VM deployment runbook
- [k3s-cluster.md](infrastructure/k3s-cluster.md) — k3s lab runbook + Headlamp

## Deployment
- [deployment.md](deployment/deployment.md) — deployment overview
- [manual-deployment.md](deployment/manual-deployment.md) — step-by-step manual deploy
- [release-automation.md](deployment/release-automation.md) — release-please + image tagging
- [containerization-adoption-plan.md](deployment/containerization-adoption-plan.md) — historical migration plan

## Operations
- [env.md](operations/env.md) — environment variables reference
- [smoke-suite.md](operations/smoke-suite.md) — smoke suite usage and structure
- [blockers.md](operations/blockers.md) — known issues and workarounds

## Where things live (quick reference)

| Topic | Path |
| --- | --- |
| Application source | `services/*/` |
| Docker compose stacks | `deployments/{local,smoke,gcp-vm,k3s}/` |
| Ansible inventories | `ansible/inventories/{gcp-vm,gcp-k3s}/` |
| Ansible playbooks | `ansible/playbooks/` |
| Tests | `tests/{unit,integration}/` |
| Frozen Hyper-V lab | `deprecated/hyperv-lab/` |
