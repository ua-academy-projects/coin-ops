# k3s_netpol
Enforces a default-deny + explicit-allow NetworkPolicy posture across all
`coinops-*` app and data namespaces. Every restricted namespace gets a
`default-deny` policy (Ingress+Egress) and an `allow-dns` egress exception so
CoreDNS resolution keeps working — omitting `allow-dns` is the most common
misconfiguration and silently breaks all service-to-service calls. Flows are
then opened exactly as needed: gateway→proxy/history-api/ui, proxy→redis+rabbitmq
+internet-80/443, history-api+history-consumer→postgres:5432, etc.

**Enforcement:** k3s ships with kube-router as its built-in NetworkPolicy
controller; no additional CNI plugin or Cilium is required. Policies take
effect as soon as they are applied.

**Postgres egress exception:** `coinops-postgres` gets Ingress restrictions
only — egress is left open. The CNPG instance manager talks to the operator
and the Kubernetes API server on ports that shift across versions; locking
egress is the #1 way to wedge a CNPG cluster and offers minimal security gain
in a lab context.

**Intentionally unrestricted:** `coinops-cloudflared` (edge tunnel — exact
Cloudflare egress ports vary by mode and are not worth guessing wrong) and the
tooling namespaces (`headlamp`, `homepage`, `hello`). Revisit once the tunnel's
egress ports are confirmed stable.

**Where it runs:** first node in the `k3s` inventory group only (`meta: end_host`
exits joiners). Applied last in `k3s-app.yml`, after `k3s_coinops` has created
the namespaces the policies target.
