# k3s Cluster Lab

This document describes the current GCP k3s learning cluster and how to verify
it. The goal of this lab is to understand Kubernetes by first bringing up a
small cluster, then inspecting and breaking it in controlled ways.

## What We Built

Infrastructure is created in the separate `gcp-terraform-bootstrap` repository.
Application and Kubernetes automation lives here in `coin-ops-dev/ansible`.

The current lab uses four GCP VMs:

| VM | IP type | Role |
| --- | --- | --- |
| `k3s-jump` | public + private | SSH bastion and HAProxy entrypoint for the Kubernetes API |
| `k3s-node-1` | private | k3s server node, control plane, embedded etcd, workload node |
| `k3s-node-2` | private | k3s server node, control plane, embedded etcd, workload node |
| `k3s-node-3` | private | k3s server node, control plane, embedded etcd, workload node |

The k3s nodes do not have public IP addresses. Local access goes through
`k3s-jump`.

```text
Mac
  |
  | kubectl / Helm / Headlamp port-forward
  v
k3s-jump:6443
  |
  | HAProxy TCP forwarding
  v
k3s-node-1:6443
k3s-node-2:6443
k3s-node-3:6443
```

Port `6443` is the Kubernetes API server port. `kubectl`, Helm, and Headlamp all
talk to Kubernetes through this API.

## Ansible Layout

The k3s automation extends the existing Ansible tree instead of creating a
separate Ansible project.

| Path | Purpose |
| --- | --- |
| `ansible/inventory.k3s.gcp` | k3s jump host and private k3s node inventory |
| `ansible/k3s-cluster.yml` | full k3s cluster playbook |
| `ansible/roles/haproxy_k3s_api` | installs HAProxy on the jump host and forwards `:6443` to the k3s nodes |
| `ansible/roles/k3s_node_prep` | prepares Linux for Kubernetes networking and runtime requirements |
| `ansible/roles/k3s_server` | installs the first k3s server and joins the remaining server nodes |
| `ansible/group_vars/k3s_jump` | jump host firewall/API variables |
| `ansible/group_vars/k3s_servers` | k3s API, subnet, and TLS variables |

For `k3s_servers`, the shared `common` role skips full OS upgrades and does not
manage UFW. Kubernetes and Flannel manage their own iptables chains, so UFW is
disabled on k3s nodes to avoid breaking pod networking. The jump host can still
use UFW because it is not part of the Kubernetes data plane.

The playbook order is:

```text
1. prepare k3s-jump and HAProxy
2. prepare all k3s Linux nodes
3. bootstrap k3s-node-1 with --cluster-init
4. read the k3s join token
5. join k3s-node-2 and k3s-node-3 as server nodes
6. verify all nodes with kubectl
```

## Important Concepts In This Cluster

### Node

A Kubernetes node is a machine that Kubernetes can use. In this lab, each node
is a GCP VM.

```bash
kubectl get nodes -o wide
```

Expected result:

```text
k3s-node-1   Ready   control-plane,etcd
k3s-node-2   Ready   control-plane,etcd
k3s-node-3   Ready   control-plane,etcd
```

`Ready` means Kubernetes sees the VM and can use it.

### Control Plane

The control plane is the management layer of Kubernetes. It receives API
requests, stores desired state, schedules pods, and reconciles the cluster.

In k3s, the control plane is packed into the `k3s` systemd service on each
server node.

```bash
kubectl cluster-info
```

The control plane address should point at the HAProxy endpoint on the jump host.

### Server Node And Worker Function

In k3s, a `server` node runs the control plane. By default, it can also run
pods. That means our three nodes are both server/control-plane nodes and
workload nodes.

Check where pods are running:

```bash
kubectl get pods -A -o wide
```

The `NODE` column shows which VM is running each pod.

### etcd

`etcd` is the Kubernetes state database. It stores nodes, pods, deployments,
services, secrets, RBAC, and other cluster state.

All three nodes have the `etcd` role, so the cluster is more resilient than a
single-server setup.

```bash
kubectl get nodes
```

Look for:

```text
ROLES
control-plane,etcd
```

### Pod

A pod is the smallest workload unit Kubernetes runs. It usually wraps one
container.

```bash
kubectl get pods -A
```

`READY 1/1` means the pod has one container and that container is ready.

## Install Or Re-run The Cluster Playbook

Install required Ansible collections:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

Check inventory connectivity:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/coin-ops-ansible-tmp \
ANSIBLE_REMOTE_TEMP=/tmp/coin-ops-ansible-tmp \
ANSIBLE_SSH_CONTROL_PATH_DIR=/private/tmp/coin-ops-ansible-cp \
ansible -i ansible/inventory.k3s.gcp k3s_servers -m ping
```

Run the k3s playbook:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/coin-ops-ansible-tmp \
ANSIBLE_REMOTE_TEMP=/tmp/coin-ops-ansible-tmp \
ANSIBLE_SSH_CONTROL_PATH_DIR=/private/tmp/coin-ops-ansible-cp \
ansible-playbook -i ansible/inventories/gcp-k3s ansible/playbooks/k3s-cluster.yml
```

## Configure kubectl

The k3s kubeconfig is generated on the first server node:

```text
/etc/rancher/k3s/k3s.yaml
```

For local use, copy it to the Mac and replace `127.0.0.1:6443` with the HAProxy
endpoint on `k3s-jump`.

For this lab, the local kubeconfig was copied to:

```text
~/.kube/config
```

After that, commands can be run directly:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

Do not commit kubeconfig files. They contain cluster access credentials.

## Headlamp

Headlamp is installed in-cluster through Helm. It is a Kubernetes UI running as
normal Kubernetes resources.

Useful checks:

```bash
helm list -n kube-system
kubectl -n kube-system get pods | grep headlamp
kubectl -n kube-system get svc | grep headlamp
kubectl -n kube-system rollout status deployment/headlamp
```

Open Headlamp locally:

```bash
kubectl -n kube-system port-forward service/headlamp 8080:80
```

Then open:

```text
http://localhost:8080
```

Create an admin token for lab access:

```bash
kubectl -n kube-system create serviceaccount headlamp-admin
kubectl create clusterrolebinding headlamp-admin \
  --serviceaccount=kube-system:headlamp-admin \
  --clusterrole=cluster-admin
kubectl -n kube-system create token headlamp-admin
```

The token is sensitive. Do not commit it and do not paste it into chat or docs.

## Verification Commands

Cluster nodes:

```bash
kubectl get nodes -o wide
```

System pods:

```bash
kubectl get pods -A -o wide
```

Kubernetes API endpoint:

```bash
kubectl cluster-info
grep "server:" ~/.kube/config
```

Current identity and permissions:

```bash
kubectl auth whoami
kubectl auth can-i get nodes
kubectl auth can-i create pods
```

Headlamp:

```bash
kubectl -n kube-system get pods | grep headlamp
kubectl -n kube-system port-forward service/headlamp 8080:80
```

## What Not To Commit

Do not commit:

- `~/.kube/config`
- `~/.kube/k3s-gcp.yaml`
- Headlamp tokens
- SSH private keys
- GCP service account JSON files
- Terraform state files
- `.env` files with secrets

The repository should contain automation, inventories, and documentation, but
not live credentials.

## Current Scope

This lab only brings up Kubernetes itself and Headlamp. The Coin-Ops application
is not migrated to Kubernetes yet. The current application deployment remains
the existing Docker Compose plus Ansible flow.

Future application work should answer:

- which services become Kubernetes deployments
- how PostgreSQL, RabbitMQ, and Redis should be handled
- how secrets move from GCP Secret Manager into Kubernetes
- whether ingress should use the default k3s Traefik or a custom controller
- how CI/CD should deploy images into the cluster
