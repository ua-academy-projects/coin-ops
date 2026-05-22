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
| k3s-1  | GCP   | private-subnet-0 | 10.10.20.40  | server + worker, `--cluster-init` |
| k3s-2  | GCP   | private-subnet-1 | 10.10.21.40  | server + worker, joins via k3s-1  |
| k3s-3  | GCP   | private-subnet-0 | 10.10.20.41  | server + worker, joins via k3s-1  |

GCP uses the `10.10.20/24` + `10.10.21/24` private subnets (AWS keeps
`10.10.10/24` + `10.10.11/24`) so the two bastions advertise non-overlapping
routes into the tailnet. The k3s nodes run **no Tailscale** — you reach them
on these private IPs through the GCP bastion's advertised route.

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
2. Fetches the Tailscale auth key from the GCP Secret Manager (used by the
   bastion only).
3. Joins the **bastion** to the tailnet and advertises the GCP private
   subnets (`cloud-bastion-stack`). The k3s nodes run no Tailscale.
4. Installs k3s, cluster-init on `k3s-1`, joins `k3s-2` and `k3s-3`
   via `--server https://k3s-1:6443`.
5. Fetches `/etc/rancher/k3s/k3s.yaml` to `~/.kube/coinops-k3s.yaml` and
   rewrites the server URL to `k3s-1`'s **private IP** (`10.10.20.40`),
   reachable from the tailnet through the bastion route.
6. Applies `roles/k3s-hello/files/k3s-hello.yaml` — namespace, deployment,
   NodePort `:30080`.
7. Deploys Headlamp (`roles/k3s-headlamp`) — an in-cluster Kubernetes web
   dashboard on NodePort `:30081`, reached through the bastion route.

## Ingress, TLS, and the app (Sprint 4)

Workloads are no longer exposed on raw NodePorts. k3s's built-in **Traefik** is
the ingress controller; **cert-manager** (installed via Helm by the
`k3s-cert-manager` role) issues real Let's Encrypt certs through a **DNS-01
ClusterIssuer backed by Cloudflare** — valid even though the cluster is private,
because DNS-01 validates over DNS, not HTTP. Every app gets a host
`<app>.lab.coinops.pp.ua` and an `Ingress` annotated with
`cert-manager.io/cluster-issuer: letsencrypt-cloudflare`.

Hosts today: `hello.`, `headlamp.`, `homepage.` (the deploy-and-expose example,
role `k3s-homepage`), and `app.` (the real Coin-Ops app, role `k3s-coinops`).
TLS terminates **on the k3s nodes** (the bastion only routes); the firewall
opens 80/443 from the bastion to the k3s tag.

**Operator prerequisites:**

1. Cloudflare-managed zone; an API token with DNS:Edit, pushed to the cloud
   secret manager as `cloudflare_token` (`./scripts/lab.sh secrets push`).
2. A wildcard DNS record `*.lab.coinops.pp.ua` → a k3s node private IP
   (e.g. `10.10.20.40`), so tailnet clients resolve the app hosts. `/etc/hosts`
   is the no-DNS fallback.
3. `terraform apply` (firewall 80/443) → `./scripts/lab.sh k3s` (cluster +
   cert-manager + hello/headlamp/homepage) → `ansible-playbook -i <gcp-inventory>
   ansible/k3s-app.yml` (the real app: postgres/rabbitmq/redis pods +
   proxy/history/ui behind the ingress).

The deploy-and-expose pattern (one role = Namespace + ConfigMap + Deployment +
Service + Ingress-TLS, applied with `kubernetes.core.k8s`) is reusable — copy
`roles/k3s-homepage` to stand up any other app.

## Verification

After a clean run, from a laptop joined to the tailnet with
`sudo tailscale up --accept-routes`:

```bash
# Cluster healthy? (reaches 10.10.20.40:6443 via the GCP bastion route)
kubectl --kubeconfig=~/.kube/coinops-k3s.yaml get nodes
# Expect: 3 nodes, all "Ready", roles "control-plane,etcd,master".

kubectl --kubeconfig=~/.kube/coinops-k3s.yaml get pods -A
# Expect: kube-system pods Running; coinops-hello/hello-* Running ×2.

# Workloads are behind the Traefik ingress with TLS now (no NodePorts).
# With *.lab.coinops.pp.ua pointed at a k3s node IP (see Ingress section):
curl -s https://hello.lab.coinops.pp.ua | head -3
curl -s https://homepage.lab.coinops.pp.ua | head -3

# Headlamp dashboard: browse to https://headlamp.lab.coinops.pp.ua and log in with:
kubectl --kubeconfig=~/.kube/coinops-k3s.yaml -n headlamp create token headlamp-admin --duration=24h
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
  only and which the bastion is allowed to reach. Worth tracing by hand.
- How a Tailscale **subnet router** lets a whole private subnet be
  reachable over the tailnet without installing the agent on every node —
  and how the bastion SNATs that traffic, so to k3s it looks like it came
  from the bastion.

## What to leave alone (for now)

- **The app here is a learning copy, not production.** Sprint 4 added
  ingress (Traefik + cert-manager) and a copy of the Coin-Ops app
  (`ansible/k3s-app.yml`) with postgres/rabbitmq/redis as in-cluster pods on
  local-path storage. There's still no managed-DB durability, no backups, and
  no observability — the customer-facing site stays on the AWS compose stack
  (`coinops.pp.ua`).
- **Don't replace `--cluster-init` with an external etcd.** The single
  embedded-etcd shape is the simplest mental model for a learning lab.
- **Don't add agent-only nodes.** Keep the symmetry — every node runs
  everything. That's the point.
