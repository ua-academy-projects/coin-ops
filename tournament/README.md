# Coin-Ops Implementation Tournament

Analysis date: 2026-04-13

Scope: all 11 remote implementation branches available after `git fetch --all --prune` from `https://github.com/ua-academy-projects/coin-ops.git`.

Update note: `origin/volynets` was rechecked after a later remote refresh on 2026-04-13. It advanced from the initial license-only state to a real VM/Ansible implementation at `1e68c6f`, so the comparison and ranking now treat it as a middle-tier implementation candidate. The recommended winner remains `origin/Shabat`.

## Branch Set

| Branch | Last inspected commit | Classification |
| --- | --- | --- |
| `origin/Shabat` | `d9cef31` | Complete candidate baseline |
| `origin/hrenchevskyi` | `124bc2c` | Strong application/container branch, weaker cloud/VM story |
| `origin/kazachuk` | `2ac6d9c` | Full app with VM and Docker modes, security/durability gaps |
| `origin/kurdupel` | `34ad94c` | Partial VM/application scaffold |
| `origin/main` | `9da75e3` | Non-implementation, license only |
| `origin/monero-privacy-system` | `dfccba1` | Strong Terraform experiment, different product/domain |
| `origin/penina` | `d1a4b65` | Documented five-VM and Docker attempt, runnable drift |
| `origin/shturyn` | `e0b90b4` | Unrelated weather proxy/frontend, no Coin-Ops infra |
| `origin/smoliakov` | `ca3c654` | VM/Ansible/AWS experiment with major hygiene issues |
| `origin/volynets` | `1e68c6f` | Strong VM/Ansible implementation, no Docker/Terraform |
| `origin/zakipnyi` | `0382ec5` | Vagrant five-VM implementation, no Docker/Terraform |

## Deliverables

- [Branch-by-branch comparison](branch-by-branch.md)
- [Ranking and decision](ranking-and-decision.md)
- [Unified future architecture](future-architecture.md)
- [Next sprint recommendations](next-sprint-plan.md)

## Method

Branches were compared as competing infrastructure and application implementations, not as personal evaluations. The analysis weights product fit because the next sprint needs a baseline the team can evolve, not just an isolated infrastructure demo.

Evaluation criteria:

- clarity and quality of architecture
- deployment reliability
- VM setup quality
- Docker maturity
- Terraform maturity and reusability
- environment reproducibility
- maintainability
- scalability
- production readiness
- AWS migration readiness
- Kubernetes readiness
- overall DevOps maturity

## Executive Decision

Recommended baseline: `origin/Shabat`.

Reason: it is the only branch that combines a coherent distributed application, Dockerized services, per-node Compose deployment, Ansible provisioning/deploy automation, Hyper-V Terraform, GHCR image publishing, persistent data handling, health checks, environment templating, and deployment documentation. It still needs production hardening, but it is the strongest starting point for an AWS and later Kubernetes path.
