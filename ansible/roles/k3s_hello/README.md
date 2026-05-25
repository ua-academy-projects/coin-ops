# k3s_hello
Deploy the hello-world learning workload — `nginxdemos/hello`, 2 replicas
behind a ClusterIP Service — into the k3s cluster on first run, then exit on
all subsequent hosts. Exposed through Traefik with a Let's Encrypt cert at
`https://hello.<domain>` (ingress only — no NodePort).

**Where it runs:** the first node in the `k3s` inventory group only
(`meta: end_host` exits all joiner hosts before any work). Applied by the
`k3s-up.yml` playbook after [[k3s]] has the cluster up and [[k3s_cert_manager]]
has the ClusterIssuer ready.

**Reads:** `k3s_first_node` and `k3s_kubeconfig`; `k3s_ingress_domain` /
`cert_manager_cluster_issuer` (shared ingress/TLS inputs); `k3s_hello_host`
(`hello.<domain>`). All in `defaults/main.yml`.

**Produces:** in the `tooling` namespace — the `hello` Deployment, a ClusterIP
Service, and a Traefik `Ingress` for `hello.<domain>` with the `hello-tls` cert
auto-issued by cert-manager.

**Reaching it:** browse to `https://hello.<domain>` from a tailnet client — the
wildcard `*.<domain>` resolves to a k3s node private IP, routed through the GCP
bastion. The cluster is never exposed to the public internet.

Manifest lives at `templates/k3s-hello.yaml.j2`. Edit there; re-running the role
re-applies it idempotently (`wait: true` blocks until the Deployment is
Available).
