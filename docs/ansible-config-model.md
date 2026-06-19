# Ansible Configuration Model

Ansible configures hosts, renders legacy VM Compose stacks, installs Kubernetes
workloads, and resolves runtime settings from Terraform output and cloud
secrets. The active AWS path runs the EKS playbooks locally during bootstrap and
from disposable Jenkins Kubernetes agents during normal operation.

## Sources of Truth

- `terraform/config/*.json`: platform policy, clouds, networks, instances, DNS, deploy defaults, and secret names.
- `terraform/config/ansible-runtime.json`: generated Terraform metadata consumed by Ansible.
- `ansible/vars/local.generated.json`: optional generated local overrides.
- `ansible/roles/*/defaults/main.yml`: role-local technical defaults.
- selected cloud secret backend: runtime passwords, registry token, Cloudflare token, and Tailscale auth key.
- Jenkins credentials/environment: the active in-cluster execution path sets
  `COINOPS_SECRET_BACKEND=env` and materializes generated runtime JSON only in
  the disposable workspace.

## Runtime Resolution

Every main playbook includes `ansible/roles/runtime_config` in `pre_tasks`. That role merges JSON config, generated metadata, environment overrides, and secrets into flat variables such as `runtime_backend`, `image_tag`, `postgres_runtime_image`, `backend_ip`, `tailscale_auth_key`, and `cloudflare_api_token`.

Keep the merge logic here. Do not copy platform settings into dynamic inventory or role tasks.

## Role Patterns

- VM Compose roles use `compose_stack` and templates from `deploy/compose/`.
- k3s roles use reusable helpers such as `k3s_helm_client`, `k3s_ingress_endpoint`, `k3s_acme_cloudflare`, and CNPG roles.
- EKS playbooks deliberately reuse many `k3s_*` workload roles. In those names,
  `k3s` is historical; the roles operate through the supplied kubeconfig and
  are not proof that the cluster is self-managed k3s.
- Runtime SQL is read from `deploy/sql/` and staged by the role that needs it.
- Tailscale and multicloud routing stay explicit host-level concerns.

## Checks

```bash
make runtime-config
make ansible-check
```

For active EKS live validation:

```bash
make eks-headlamp
make eks-coinops
```

In normal operation run only the affected Jenkins job instead. Files under
`ansible/artifacts/` and `terraform/config/ansible-runtime.json` are generated,
sensitive local artifacts and must remain ignored.
