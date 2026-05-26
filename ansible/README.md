# Ansible Layout

This directory contains the k3s and Kubernetes deployment automation for
CoinOps.

## Main Playbooks

| Playbook | Purpose |
| --- | --- |
| `k3s-cluster.yml` | Bootstraps the 3-node HA k3s cluster on existing GCP VMs |
| `k3s-platform.yml` | Installs platform components such as cert-manager and Homepage |
| `coinops-app.yml` | Deploys the real CoinOps application into k3s |

## Inventory

| Inventory | Purpose |
| --- | --- |
| `inventory.k3s.gcp` | GCP k3s cluster layout with jump host access |

## k3s Cluster Roles

| Role | Purpose |
| --- | --- |
| `common` | Shared Linux preparation used by the jump host and k3s nodes |
| `haproxy_k3s_api` | Installs HAProxy on the jump host and forwards Kubernetes API traffic |
| `k3s_node_prep` | Prepares Linux networking settings required by Kubernetes |
| `k3s_server` | Installs the first k3s server and joins the remaining server nodes |

## Platform Roles

| Role | Purpose |
| --- | --- |
| `cert_manager` | Installs cert-manager with Helm |
| `cert_manager_issuer` | Creates Cloudflare DNS-01 ClusterIssuers |
| `homepage` | Deploys the Homepage dashboard app |
| `homepage_ingress` | Exposes Homepage through Traefik Ingress |

## CoinOps App Roles

| Role | Purpose |
| --- | --- |
| `cnpg_operator` | Installs the CloudNativePG operator with Helm |
| `coinops_data` | Creates namespaces, secrets, CNPG PostgreSQL, RabbitMQ, and Redis |
| `coinops_proxy` | Deploys the Go proxy |
| `coinops_history` | Deploys history API and history consumer |
| `coinops_ui` | Deploys the React UI |
| `coinops_ingress` | Creates public Ingress rules and TLS routing for CoinOps |

## CoinOps App Tags

Use tags when only one layer needs to be changed.

```bash
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags cnpg
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags data
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags backend
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags frontend
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags ingress
```

## Variable Convention

Role variables are stored in each role's `defaults/main.yml` and start with the
role name. Examples:

```text
coinops_data_postgres_cluster_name
coinops_proxy_image_tag
coinops_ingress_domain
cnpg_operator_chart_version
```

This keeps variables readable and avoids accidental name collisions between
roles.

## Local Kubernetes Execution

The Kubernetes playbooks run on `localhost`. Ansible does not SSH into a node to
run Helm-wrapped application installs. Instead, it uses the local kubeconfig and
calls the Kubernetes API directly through Ansible modules:

- `kubernetes.core.helm` for Helm charts
- `kubernetes.core.k8s` for Kubernetes manifests
- `kubernetes.core.k8s_info` for read/verify steps
