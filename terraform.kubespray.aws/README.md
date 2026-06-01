# AWS Kubespray Infrastructure

This standalone Terraform package creates an AWS layout intended for Kubespray
with:

- 1 bastion host in a public subnet
- 3 private Kubernetes nodes
- 2 public subnets for the external load balancer
- 2 private subnets for the cluster nodes
- 1 NAT gateway for outbound traffic from private nodes
- 1 public Application Load Balancer for ingress traffic

The generated Kubespray inventory uses `ProxyJump` through the bastion host and
treats all three cluster nodes as:

- control-plane nodes
- etcd members
- schedulable kube nodes

## Created Components

- `bastion`
- `cp-1`
- `cp-2`
- `cp-3`
- public ALB for ingress

## Network Model

- `public-a`, `public-b`:
  - ALB
  - bastion
  - NAT gateway
- `private-a`, `private-b`:
  - Kubernetes nodes

Kubespray accesses the private nodes through the bastion. External HTTP/HTTPS
traffic goes to the ALB, then to ingress-nginx `NodePort` on the cluster.

## Usage

```bash
cd terraform.kubespray.aws
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

## End-to-End Lab Flow

### 1. Create the AWS infrastructure

```bash
cd terraform.kubespray.aws
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

### 2. Generate Kubespray inventory

```bash
terraform output -raw kubespray_inventory_ini > /home/valentyn/Test/kubespray/inventory/coinops/inventory.ini
```

### 3. Install Kubernetes with Kubespray

```bash
cd /home/valentyn/Test/kubespray
. .venv/bin/activate
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
ansible-playbook -i inventory/coinops/inventory.ini \
  --become --become-user=root \
  -e ansible_ssh_private_key_file=~/.ssh/id_rsa \
  cluster.yml
```

### 4. Connect `kubectl` through the bastion

Run the tunnel in one terminal and keep it open:

```bash
cd /home/valentyn/Test/coin-ops/terraform.kubespray.aws
terraform output -raw kubectl_tunnel_command
```

In another terminal, copy the admin kubeconfig from `cp-1`:

```bash
mkdir -p ~/.kube
ssh -J ubuntu@$(terraform output -raw bastion_public_ip) \
  -i ~/.ssh/id_rsa \
  ubuntu@$(terraform output -json cluster_private_ips | jq -r '.["cp-1"]') \
  'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes
```

## Important Variables

- `allowed_source_cidr` - your public `/32` for bastion SSH and API access
- `ami_id` - base AMI for bastion and nodes
- `instance_type` - EC2 size for Kubernetes nodes
- `bastion_instance_type` - EC2 size for bastion
- `tls_certificate_arn` - optional ACM certificate for ALB HTTPS

## Kubespray Inventory

Generate inventory:

```bash
terraform output -raw kubespray_inventory_ini > inventory.ini
```

The generated inventory already contains:

- private `ansible_host` values for cluster nodes
- `ProxyJump` through the bastion

## Ingress

This package does not install ingress-nginx itself, but it prepares AWS for it:

- ALB listener on `80`
- optional ALB listener on `443`
- security-group rules from ALB to cluster node `NodePort`

Install ingress-nginx after the cluster is ready:

```bash
terraform output -raw ingress_nginx_helm_command
```

Then apply that command.

The current output already uses the correct Helm syntax:

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443
```

Verify it:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

## Homepage

Deploy Homepage from the repo root:

```bash
cd /home/valentyn/Test/coin-ops
source .env
HOMEPAGE_HOST=homepage.smolyakov-devops.pp.ua ./scripts/deploy-homepage.sh
```

Notes:

- the script applies the Kubernetes manifests
- restarts the `homepage` deployment
- creates or updates the Cloudflare `CNAME`
- the Cloudflare step requires `CLOUDFLARE_API_TOKEN`

Verify it:

```bash
kubectl get pods -n homepage
kubectl logs -n homepage deploy/homepage --tail=50
kubectl get ingress -n homepage
```

## Headlamp

The repo also contains `k8s/headlamp/` and `scripts/deploy-headlamp.sh` for a
private-only Headlamp deployment.

- Headlamp is exposed as a fixed `NodePort`
- the node port is reachable only from the bastion security group
- there is no public ingress and no public DNS for it

Deploy it with:

```bash
cd ..
./scripts/deploy-headlamp.sh
```

Then create a login token for the Headlamp service account:

```bash
kubectl create token headlamp -n headlamp
```

Use that token in the Headlamp UI after opening the local tunnel.

Then open the private tunnel command from Terraform:

```bash
terraform output -raw headlamp_tunnel_command
```

With that tunnel running, open:

```text
http://127.0.0.1:30082
```

## Useful Outputs

- `bastion_public_ip`
- `cluster_private_ips`
- `load_balancer_dns_name`
- `kubespray_inventory_ini`
- `ingress_nginx_helm_command`
- `kubectl_tunnel_command`
- `headlamp_tunnel_command`

`kubectl_tunnel_command` opens a local tunnel to the API server through the
bastion and lands on `127.0.0.1:6443` on `cp-1`, which matches the default
Kubernetes API certificate SANs better than exposing the private node IP
directly.
