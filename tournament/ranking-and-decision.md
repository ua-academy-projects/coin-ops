# Ranking and Decision

Delta recheck: on 2026-04-14, `origin/tsyhan`, `origin/kurdupel`, and `origin/volynets` were refreshed and re-evaluated from non-Markdown artifacts only. Participant README/report files were not used as evidence. API topic is not a scoring factor; the important questions are component quality, reproducibility, deployment maturity, and cloud/Kubernetes migration readiness.

Score scale: `0` means absent, `1` means prototype/very weak, `3` means usable for demo, `5` means strong for the tournament context. Scores are relative to this internship repository, not to a production-grade platform.

Column legend:

- `Arch`: architecture clarity and application fit
- `Deploy`: deployment reliability
- `VM`: VM setup quality
- `Docker`: Docker maturity
- `TF`: Terraform maturity and reusability
- `Repro`: environment reproducibility
- `Maint`: maintainability
- `Scale`: scalability
- `Prod`: production readiness
- `AWS`: AWS migration readiness
- `K8s`: Kubernetes readiness
- `DevOps`: overall DevOps maturity

## Score Matrix

| Rank | Branch | Arch | Deploy | VM | Docker | TF | Repro | Maint | Scale | Prod | AWS | K8s | DevOps | Total | Baseline eligibility |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | `origin/Shabat` | 5 | 4 | 4 | 4 | 3 | 4 | 4 | 3 | 3 | 3 | 3 | 4 | 44 | Yes |
| 2 | `origin/hrenchevskyi` | 4 | 3 | 2 | 4 | 1 | 3 | 4 | 3 | 2 | 2 | 2 | 3 | 33 | Partial |
| 3 | `origin/tsyhan` | 3 | 2 | 4 | 3 | 4 | 3 | 3 | 2 | 2 | 2 | 2 | 3 | 33 | Partial, infra/reference |
| 4 | `origin/kazachuk` | 4 | 3 | 3 | 3 | 1 | 3 | 3 | 2 | 2 | 2 | 2 | 3 | 31 | Partial |
| 5 | `origin/volynets` | 4 | 4 | 4 | 0 | 0 | 3 | 4 | 2 | 3 | 1 | 1 | 3 | 29 | Partial, VM/Ansible only |
| 6 | `origin/zakipnyi` | 3 | 2 | 3 | 0 | 0 | 2 | 2 | 2 | 1 | 1 | 1 | 2 | 19 | No, VM-only prototype |
| 7 | `origin/kurdupel` | 3 | 2 | 4 | 0 | 0 | 2 | 2 | 1 | 1 | 0 | 0 | 2 | 17 | No, VM-only and fragile |
| 8 | `origin/penina` | 3 | 1 | 2 | 1 | 0 | 1 | 2 | 2 | 1 | 1 | 1 | 2 | 17 | No, reproducibility broken |
| 9 | `origin/smoliakov` | 2 | 1 | 2 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 12 | No, hygiene/security risk |
| 10 | `origin/shturyn` | 1 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 3 | No, missing infra |
| 11 | `origin/main` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | No implementation |

## Recommended Winner

Winner: `origin/Shabat`.

`origin/Shabat` should become the baseline for the next sprint because it is the only branch that already ties together the main layers the team needs:

- real distributed application shape
- service boundaries that can map to containers, cloud services, and later Kubernetes workloads
- Docker images for custom services
- per-node Compose deployment
- Ansible roles for provisioning and deployment
- Terraform-based VM creation
- GHCR image build workflow
- persistent state handling
- runtime environment templating
- health probing and operational runbooks to add next

It is not production-ready yet. The decisive point is that its remaining work is mostly hardening and cloud migration, while most other branches require first rebuilding basic reproducibility, secrets, deployment shape, or even application fit.

## Runner-Up Notes

`origin/hrenchevskyi` is the best source of application-level and operational practices after the winner. It has clean config handling, security headers, rate limiting, a useful runbook, Ansible Vault usage, and good Dockerfile structure. Its downside is that it is a hybrid local Docker plus database VM design with no Terraform or full cloud path.

`origin/kazachuk` is the best source of full-stack Docker Compose and dual VM/Docker deployment ideas. It is held back by hardcoded secrets and weak queue durability/ack semantics.

`origin/tsyhan` replaces the old `origin/monero-privacy-system` branch in this evaluation. Ignoring API topic, it moves up because the updated branch now has a fuller local Docker Compose stack, Redis-backed sessions, RabbitMQ, and the cleanest Terraform/libvirt structure outside the winner. It ties `origin/hrenchevskyi` numerically in the simple matrix, but loses the tie-break for baseline usefulness because hrenchevskyi has stronger queue-backed persistence semantics. It still is not the baseline: the worker writes directly to PostgreSQL and only publishes a RabbitMQ notification after commit, so RabbitMQ is not the persistence boundary; production deploy still relies on VM cron/Git polling; Terraform is libvirt-specific; and `terraform/variables.tf` still defaults to the deleted `monero-privacy-system` branch name.

`origin/volynets` improves again after the 2026-04-14 recheck. The new code adds root-owned environment files, service restart handlers, Gunicorn for the web UI, graceful shutdown paths in the Go services, and richer chart/history UI modes. It is now the strongest VM/systemd/Ansible implementation outside the top container/IaC branches. It still lacks Docker, Terraform, CI, registry-based delivery, Redis, and cloud packaging, so it is a component/reference source rather than the baseline.

`origin/kurdupel` is no longer just a partial scaffold. It now has a four-VM Vagrant topology plus Ansible roles for common packages, PostgreSQL, RabbitMQ, Redis, proxy, history, and UI systemd services. It remains below the stronger candidates because the deployment runs from `/vagrant`, inventory contains host-specific private-key paths, Redis protected mode is disabled, PostgreSQL provisioning relies heavily on shell SQL, there is no Docker/Terraform/CI, and the history consumer ACKs even when `saveToDB` logs an insert error.

`origin/zakipnyi` remains a useful VM-only reference, but `origin/volynets` is stronger now because its Ansible automation, firewall rules, and consumer idempotency are cleaner.

## Decision Summary

Use `origin/Shabat` as the integration baseline.

Borrow selectively:

- From `origin/hrenchevskyi`: config validation, security headers, rate limiting, runbook style, and Ansible Vault thinking.
- From `origin/kazachuk`: full-stack local Compose, named volumes, and health-gated dependency startup.
- From `origin/tsyhan`: Terraform/cloud-init structure, Pydantic settings, structlog usage, and local Docker Compose shape for Redis/RabbitMQ/PostgreSQL.
- From `origin/volynets`: five-VM Ansible separation, UFW source restrictions, root-only env files, Gunicorn/systemd service shape, graceful shutdown, and Go consumer transaction/ack pattern.
- From `origin/kurdupel`: simple role-per-service Ansible layout as a teaching/reference pattern only, not as a cloud baseline.
- From `origin/zakipnyi`: five-role topology as a possible future scaling reference.

Do not directly baseline `penina`, `smoliakov`, `kurdupel`, `shturyn`, or `main`. Treat `tsyhan` as the strongest Terraform/observability reference and `volynets` as the strongest VM/Ansible reference, not as main baselines for AWS/Kubernetes work.
