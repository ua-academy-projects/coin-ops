# k3s-hello

Deploy the hello-world learning workload — `nginxdemos/hello`, 2 replicas,
NodePort `:30080` — into the k3s cluster on first run, then exit on all
subsequent hosts.

**Where it runs:** the first node in the `k3s` inventory group only
(`meta: end_host` exits all joiner hosts before any work). Applied by the
[[k3s-cluster]] meta-role after [[k3s]] has the cluster up.

**Reads:** `k3s_first_node` from [[k3s]]'s defaults.

**Produces:** the `coinops-hello` namespace, the `hello` Deployment, and
the NodePort Service reachable on `:30080` on every node IP — both
private VPC IP and tailnet `100.x` IP. The GCP firewall rule
`k3s_nodeport_from_tailnet` opens `:30080` to the tailnet so any joined
client can curl the workload.

Manifest lives at `files/k3s-hello.yaml`. Edit there; re-running the role
re-applies the file idempotently.
