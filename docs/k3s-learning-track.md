# k3s learning track

This document explains what the k3s cluster on GCP **is** and what it
deliberately **is not**, so anyone reading the deployment configuration
doesn't mistake the learning sandbox for a production target.

## What this is

A 3-node HA Kubernetes cluster running on GCP (`europe-central2`), built
with k3s. Every node is **both** control-plane and worker (HA k3s with
embedded etcd, no server/agent split). The cluster runs a single
deliberately-trivial workload — `nginxdemos/hello` on NodePort `:30080` —
purely to prove the cluster works end-to-end.

Operators reach the cluster over the **Tailscale** tailnet — `kubectl`
from any joined laptop talks straight to the first node's `100.x` IP on
`:6443`. The fetched kubeconfig is already rewritten to that IP by the
Ansible `k3s` role. No bastion ProxyJump needed for kubectl; SSH still
uses the bastion the usual way.

## What this is not

It is **not** the new production runtime. The customer-facing demo —
`coinops.pp.ua` — still runs on the AWS cloud-native compose stack
deployed by `ansible/cloud-deploy.yml` against the AWS managed services
(RDS / SQS / ALB / ACM / Valkey / Secrets Manager). That deployment is
untouched by k3s.

The repo's own `docs/containerization-adoption-plan.md` (written earlier
in the cohort) argued explicitly against k3s as the production target.
This learning track does not contradict that — it satisfies one of the
re-evaluation criteria that same doc lists: *"you want Kubernetes
specifically as a learning/demo objective."*

## Topology

| Node   | Cloud | Subnet           | Private IP   | Role                       |
|--------|-------|------------------|--------------|----------------------------|
| k3s-1  | GCP   | private-subnet-0 | 10.10.10.40  | server + worker, `--cluster-init` |
| k3s-2  | GCP   | private-subnet-0 | 10.10.10.41  | server + worker, joins via k3s-1  |
| k3s-3  | GCP   | private-subnet-1 | 10.10.11.40  | server + worker, joins via k3s-1  |

Three nodes is the minimum for HA etcd quorum (tolerates one node down).
All three nodes also schedule workloads — no control-plane taint — which
is the right shape for a learning lab: every node visibly does
*everything*.

Sizing: `small` (`e2-small`, 2 vCPU / 2 GB) per node. Enough for the
control-plane + a couple of demo pods. Bump to `e2-medium` if you start
running real workloads on it.

## Bring-up

The Tailscale + k3s plumbing lives entirely in Ansible + Terraform — see
`tailscale/README.md` for the auth-key flow and the cross-cloud workspace
pattern. Once that's in place:

```bash
# 0. Have the GCP terraform workspace already applied (cloud: gcp).
#    See tailscale/README.md → Cross-cloud bring-up runbook.

# 1. Source the env that points Ansible at the GCP-generated inventory.
source .env

# 2. Bring up the cluster.
ansible-playbook -i <generated-gcp-inventory> ansible/k3s-up.yml
```

The play does, in order:

1. Validates required env vars on the controller.
2. Fetches the Tailscale auth key from the GCP Secret Manager.
3. Joins the bastion to the tailnet (`cloud-bastion-stack`).
4. Joins all three k3s nodes to the tailnet (the `tailscale` role
   imported by `k3s-cluster`).
5. Installs k3s, cluster-init on `k3s-1`, joins `k3s-2` and `k3s-3`
   via `--server https://k3s-1:6443`.
6. Fetches `/etc/rancher/k3s/k3s.yaml` to `~/.kube/coinops-k3s.yaml` and
   rewrites the server URL to `k3s-1`'s tailnet IP.
7. Applies `roles/k3s-hello/files/k3s-hello.yaml` — namespace, deployment,
   NodePort.

## Verification

After a clean run, from a tailnet-joined laptop:

```bash
# Cluster healthy?
kubectl --kubeconfig=~/.kube/coinops-k3s.yaml get nodes
# Expect: 3 nodes, all "Ready", roles "control-plane,etcd,master".

kubectl --kubeconfig=~/.kube/coinops-k3s.yaml get pods -A
# Expect: kube-system pods Running; coinops-hello/hello-* Running ×2.

# Hello-world reachable on every node, over the tailnet:
for ip in $(tailscale status | awk '/coinops-lab-k3s/ {print $1}'); do
  echo "$ip:"; curl -s "http://${ip}:30080" | head -3
done
```

The two hello pods should be distributed across at least two of the
three nodes (`kubectl -n coinops-hello get pods -o wide`) — proves no
node is tainted or otherwise unschedulable.

## What to learn from this

- How `--cluster-init` vs `--server` differs at first apply, and how the
  embedded etcd is bootstrapped from a single shared token.
- Why every node listening on 6443 *and* every node listening on the
  NodePort lets the cluster survive losing the first node — and why that
  isn't true with the default agent topology.
- Where firewall rules sit in this architecture
  (`gcp-stack/modules/security/main.tf`): which ports are intra-cluster
  only, which are bastion-only, which are tailnet-open. Worth tracing by
  hand.
- How the kubeconfig's `server:` URL changes the operator experience
  (raw private IP from inside the VPC vs tailnet IP from anywhere).

## What to leave alone (for now)

- **Don't deploy real workloads here.** This cluster doesn't have
  ingress (no ALB/cert-manager), no persistent storage backend beyond
  local disk, and no observability. Production-shaped work belongs on
  the AWS compose stack until/unless the next sprint promotes k3s to a
  production target.
- **Don't replace `--cluster-init` with an external etcd.** The single
  embedded-etcd shape is the simplest mental model for a learning lab.
- **Don't add agent-only nodes.** Keep the symmetry — every node runs
  everything. That's the point.
