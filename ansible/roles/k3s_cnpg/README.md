# k3s_cnpg
Install the [CloudNativePG](https://cloudnative-pg.io) (CNPG) operator from its
official Helm chart (`cnpg/cloudnative-pg`, repo
`https://cloudnative-pg.github.io/charts`). CNPG manages PostgreSQL
declaratively as a `Cluster` custom resource — primary + replicas with
automated failover, in-cluster TLS, and rolling minor-version upgrades —
replacing the hand-rolled postgres StatefulSet.

**Where it runs:** the first node in the `k3s` inventory group only
(`meta: end_host` exits joiners). Applied by the `k3s-app.yml` playbook, before
[[k3s_coinops_data]] (which declares the actual `Cluster`).

**Reads** (all in `defaults/main.yml`): `k3s_cnpg_chart_version` (pinned chart,
`0.28.2`), `k3s_cnpg_namespace` (`cnpg-system`), `k3s_first_node`,
`k3s_kubeconfig`.

**Produces:** the CNPG operator Deployment + webhook in `cnpg-system`, and the
`postgresql.cnpg.io` CRDs (`Cluster`, `Pooler`, `Backup`, `ScheduledBackup`,
`Database`, …). The role waits for the `clusters.postgresql.cnpg.io` CRD to be
Established so the Cluster CR applied next isn't rejected by a not-yet-ready
API.

This role only installs the operator. The Coin-Ops PostgreSQL `Cluster` itself
(name `coinops-pg`, instances + storage + initdb bootstrap) is declared by
[[k3s_coinops_data]]; the app connects to the `coinops-pg-rw` read-write
Service.
