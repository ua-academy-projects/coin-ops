# k3s_kyverno

Install Kyverno (Helm) on the first k3s node and apply three ClusterPolicies that
enforce the cluster's own conventions:

1. `generate-baseline-deny` — auto-creates a `kyverno-baseline-deny` deny-all
   NetworkPolicy in every namespace labelled `coinops-tier=app`.
2. `disallow-sa-token-automount` — requires pods in app namespaces to set
   `automountServiceAccountToken: false` at the pod level (blocks pods that omit
   it or set it true).
3. `require-app-name-label` — requires `app.kubernetes.io/name` on workloads.

Policies 2–3 honour `k3s_kyverno_validation_action` (default `Enforce`; set to
`Audit` for a safe first roll-out) and exempt the platform namespaces in
`k3s_kyverno_exempt_namespaces`. The coinops-app chart already satisfies all
three, so ArgoCD syncs cleanly — the rules and the deployed reality agree.

Runs once on the first node (`meta: end_host` on joiners). Requires `k3s_tools`.
