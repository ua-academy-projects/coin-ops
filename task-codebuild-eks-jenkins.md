# Task: CodeBuild → Terraform → EKS → Jenkins (Helm + JCasC) → App Deploy via Ansible

**Project:** CoinOps — Coin Rates Monitoring System
**Cloud:** AWS
**Budget:** 10-12 hours, doing this properly (not rushed)
**Access method:** Tailscale (no public LoadBalancer/Ingress needed)
**Secrets:** AWS SSM Parameter Store (not Secrets Manager — simpler, already used for cloudwatch_agent_config)

---

## STATUS — what's actually done vs. what needs rework

### ✅ Done and verified
- `group_vars` → inventory refactor (separate cleanup, unrelated to EKS)
- Terraform `aws_eks/` module: cluster + node group + 2 IAM roles (cluster, node)
- EKS cluster live: `coinops-eks`, 2 worker nodes `Ready` (`kubectl get nodes` confirmed)
- `aws_codebuild_project` defined in Terraform, not clicked together in Console
- CodeBuild IAM role (`coinops-codebuild-role`) separate from `terraform-sa`, least-privilege via shared `TerraformCoinOpsPolicy`
- `db_password` and SSH public key passed into CodeBuild via environment variables (PLAINTEXT type — see note below), not committed to git
- A `terraform apply` run through CodeBuild (not from a laptop) succeeded end-to-end for the AWS modules

### ❌ Done wrong — needs correction
- **Jenkins was `helm install`-ed manually from a local terminal.** This directly violates the task's explicit "What NOT to do" list: *"Виконувати kubectl apply локально зі свого ноутбука"* and *"в нього ж задеплоїти Дженкінс"* (CodeBuild must do this, not a human running Helm by hand).
  → **Fix:** `helm upgrade --install jenkins ...` must be a command inside `buildspec.yml`, executed by CodeBuild's IAM role.
- **JCasC did not actually apply** — referenced `${JENKINS_ADMIN_ID}`/`${JENKINS_ADMIN_PASSWORD}` env vars that were never defined anywhere, so Jenkins fell back to its manual first-run setup wizard (`/securityRealm/firstUser`). This is the opposite of "Jenkins must have an administrator without manual button-clicking."
  → **Fix:** write a JCasC config that actually resolves — credentials sourced from SSM Parameter Store via IRSA, not from undefined placeholders.
- **Proposed hardcoding the Jenkins admin password directly in `values.yaml`.** Caught before committing — this would have violated *"Зберігати паролі у git"* (explicitly forbidden). Not done, but flagging it as a near-miss worth remembering.
  → **Fix:** SSM Parameter Store + IRSA, see below.

### ⏳ Not started yet
- OIDC provider for the EKS cluster (prerequisite for IRSA — pods assuming IAM roles)
- IAM role for Jenkins pod (IRSA) to read SSM parameters
- Real JCasC: security realm + Jenkins credentials (Git, kubeconfig context) + Pipeline job definition, all declared as code
- Tailscale sidecar/container for Jenkins access (no public ALB/Ingress)
- `Jenkinsfile` whose deploy stage calls existing `ansible-playbook` — not reimplemented logic
- Re-checking whether old k3s-specific Ansible roles (UFW rules, k3s bootstrap assumptions) need adjustment for EKS worker nodes
- EBS CSI Driver + StorageClass (so Jenkins `persistence: true` actually works instead of staying Pending forever)
- Nice-to-have, lower priority: ECR repository, Route53 records

---

## REVISED ORDER OF WORK (given the rework needed)

1. **OIDC provider + IRSA setup** — prerequisite for everything secrets-related. Without this, pods in EKS have no clean way to assume an IAM role; we'd be back to hardcoding credentials, which is explicitly forbidden.
2. **EBS CSI Driver + StorageClass** — needed so Jenkins persistence works without PVCs hanging in `Pending`. Small, self-contained, do it before Jenkins so we don't reinstall Jenkins twice.
3. **SSM Parameters** for: Jenkins admin password, GitHub credentials for the pipeline job (created via Terraform `aws_ssm_parameter`, value passed in via CodeBuild env var at apply time — same pattern as `db_password`, just stored properly afterward instead of living only as a CodeBuild env var).
4. **Tailscale container** — sidecar or separate Deployment, joins the same Tailscale network as your laptop, gives you a private hostname to reach Jenkins without any public-facing LoadBalancer.
5. **Real JCasC** — security realm pulling the admin password from the mounted SSM value (via Kubernetes Secret synced from SSM, or via JCasC's `readFileFromUrl`/Kubernetes secret reference — needs to actually resolve, tested before moving on).
6. **buildspec.yml rework** — add `kubectl`/`helm` install, `aws eks update-kubeconfig`, `helm upgrade --install jenkins ...` as real steps CodeBuild runs. This is the part that makes "CodeBuild deploys Jenkins" literally true instead of something a human did by hand.
7. **JCasC Pipeline job definition** — declares the Jenkins job pointing at the GitHub repo, so the job exists without manually creating it in the UI.
8. **Jenkinsfile** — deploy stage calls `ansible-playbook -i ansible/inventory ansible/k3s-apps.yml` (name TBD pending the re-check in step 9).
9. **Re-check Ansible roles against EKS nodes** — UFW rules and k3s-bootstrap-specific roles were written for self-managed EC2 nodes; EKS worker nodes may need different handling (e.g., security groups instead of UFW, no k3s-specific bootstrap needed at all since the control plane is AWS-managed).
10. **End-to-end test**: trigger CodeBuild from scratch (ideally from a clean state, or at least a fresh `helm upgrade`) and confirm the full chain — Terraform → EKS → Jenkins → Ansible → app running — works without any manual step in between.

---

## Theory notes for new pieces (so the "why" is clear before writing code)

**OIDC provider / IRSA** — EKS doesn't automatically let pods running inside it assume AWS IAM roles. To allow that safely, AWS uses OIDC (OpenID Connect): the EKS cluster exposes an OIDC endpoint, you register that endpoint as an "identity provider" in IAM, and then a Kubernetes ServiceAccount can be annotated to assume a specific IAM role. This is how a Jenkins pod can read an SSM parameter without ever holding a static AWS access key — it gets temporary, automatically-rotated credentials scoped to exactly the one permission it needs (`ssm:GetParameter` on one specific parameter path, nothing else).

**SSM Parameter Store vs. Secrets Manager** — both store secrets, but Parameter Store is simpler and free for standard parameters (Secrets Manager charges per secret and adds automatic rotation, which we don't need here). You already used Parameter Store for `cloudwatch_agent_config`, so this keeps a consistent pattern across the project instead of introducing a second secrets mechanism.

**EBS CSI Driver** — EKS does not ship with a default storage provisioner. A PersistentVolumeClaim with no CSI driver installed just sits in `Pending` forever — this is exactly the failure we hit earlier. The driver is the bridge between "Kubernetes wants a volume" and "AWS actually creates an EBS volume and attaches it to the right node." It needs its own IAM role (also via IRSA) and is installed as an EKS addon.

**Tailscale sidecar** — instead of exposing Jenkins to the public internet (LoadBalancer with an open port, or Ingress with a domain + TLS cert), a small Tailscale container joins your private mesh network and routes traffic to Jenkins over an encrypted tunnel. No inbound ports opened on AWS's side at all — the security group for the Jenkins pod stays closed to the internet entirely. This is meaningfully more secure for a demo/personal project than provisioning a public ALB just to reach a Jenkins UI you're the only one using.

**Why JCasC failing silently matters** — JCasC is supposed to make Jenkins fully self-configuring on every boot. If a `${VAR}` placeholder doesn't resolve, JCasC doesn't always throw a loud error — Jenkins can just skip that config block and fall back to needing a human to click through setup. This is exactly the trap we hit. Going forward, every JCasC value needs to be checked end-to-end (env var actually set → actually reaches the pod → actually gets substituted) before assuming it works, not just "the YAML is syntactically valid."

---

## Updated time estimate (rework + remaining pieces)

| Piece | Time |
|---|---|
| OIDC provider + IRSA (Terraform: `aws_iam_openid_connect_provider`, IAM roles for Jenkins + EBS CSI) | 45–60 min (new resource type, expect at least one IAM trust-policy syntax issue) |
| EBS CSI Driver addon + StorageClass | 20–30 min |
| SSM Parameters for Jenkins secrets (Terraform `aws_ssm_parameter`, least-privilege read policy) | 20–30 min |
| Tailscale container setup (auth key as SSM param, sidecar manifest or separate Deployment) | 30–45 min |
| Real JCasC (security realm resolving from actual secret, tested) | 45–60 min |
| `buildspec.yml` rework (kubectl/helm install, kubeconfig, helm upgrade as CodeBuild steps) | 20–30 min |
| JCasC Pipeline job definition | 20–30 min |
| `Jenkinsfile` calling existing Ansible | 20–30 min |
| Re-check/adjust Ansible roles for EKS nodes (UFW vs. security groups, drop k3s-bootstrap role) | 30–60 min — genuine unknown, first time touching this |
| End-to-end test + IAM/networking debugging | 1–2 hrs (this category has been the slowest every time so far) |
| **Total remaining** | **roughly 5–7.5 hours** |

This fits comfortably inside the 10–12 hour budget, including buffer for at least 2-3 more IAM permission cycles (the recurring pattern all session).
