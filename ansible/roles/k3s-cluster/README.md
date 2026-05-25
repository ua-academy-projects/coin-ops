# k3s-cluster

Full lifecycle for the GCP k3s learning cluster: system prep + Tailscale +
HA k3s server install + hello-world workload.

Applied to `hosts: k3s` by `ansible/k3s-up.yml`.

Imports: [[common]], [[k3s]], [[k3s-hello]].

No `tailscale` import — k3s nodes are private and run no Tailscale. kubectl
reaches them on their private IPs through the GCP bastion's advertised
tailnet route (see [[cloud-bastion-stack]] and the [[tailscale]] role default
`tailscale_advertise_routes`, fed by terraform's `coinops_bastion_advertise_routes`).

No `docker` or `registry-login` imports — the cluster nodes don't run
docker-compose (k3s ships its own containerd). They also don't pull from
GHCR for the hello workload (`nginxdemos/hello` is on Docker Hub, public),
so no registry auth needed.
