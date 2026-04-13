# Ranking and Decision

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
| 3 | `origin/kazachuk` | 4 | 3 | 3 | 3 | 1 | 3 | 3 | 2 | 2 | 2 | 2 | 3 | 31 | Partial |
| 4 | `origin/monero-privacy-system` | 2 | 2 | 3 | 3 | 4 | 3 | 2 | 2 | 2 | 2 | 2 | 3 | 30 | No, product mismatch |
| 5 | `origin/zakipnyi` | 3 | 2 | 3 | 0 | 0 | 2 | 2 | 2 | 1 | 1 | 1 | 2 | 19 | No, VM-only prototype |
| 6 | `origin/penina` | 3 | 1 | 2 | 1 | 0 | 1 | 2 | 2 | 1 | 1 | 1 | 2 | 17 | No, reproducibility broken |
| 7 | `origin/smoliakov` | 2 | 1 | 2 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 12 | No, hygiene/security risk |
| 8 | `origin/kurdupel` | 2 | 1 | 2 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 0 | 1 | 9 | No, partial scaffold |
| 9 | `origin/shturyn` | 1 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 3 | No, wrong project |
| 10 | `origin/main` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | No implementation |
| 10 | `origin/volynets` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | No implementation |

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
- health probing and operational documentation

It is not production-ready yet. The decisive point is that its remaining work is mostly hardening and cloud migration, while most other branches require first rebuilding basic reproducibility, secrets, deployment shape, or even application fit.

## Runner-Up Notes

`origin/hrenchevskyi` is the best source of application-level and operational practices after the winner. It has clean config handling, security headers, rate limiting, a useful runbook, Ansible Vault usage, and good Dockerfile structure. Its downside is that it is a hybrid local Docker plus database VM design with no Terraform or full cloud path.

`origin/kazachuk` is the best source of full-stack Docker Compose and dual VM/Docker deployment ideas. It is held back by hardcoded secrets and weak queue durability/ack semantics.

`origin/monero-privacy-system` is not a baseline candidate because it is a different product. It is still worth mining for Terraform/cloud-init organization ideas.

`origin/zakipnyi` is the cleanest VM-only reference after the top three. It is useful for understanding a five-VM topology, but it has no Docker or cloud migration base.

## Decision Summary

Use `origin/Shabat` as the integration baseline.

Borrow selectively:

- From `origin/hrenchevskyi`: config validation, security headers, rate limiting, runbook style, and Ansible Vault thinking.
- From `origin/kazachuk`: full-stack local Compose, named volumes, and health-gated dependency startup.
- From `origin/monero-privacy-system`: cloud-init structure and Terraform output ergonomics.
- From `origin/zakipnyi`: five-role topology as a possible future scaling reference.

Do not directly baseline `penina`, `smoliakov`, `kurdupel`, `shturyn`, `main`, or `volynets`.

