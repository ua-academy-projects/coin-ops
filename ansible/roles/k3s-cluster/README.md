# k3s-cluster

Full lifecycle for the GCP k3s learning cluster: system prep + Tailscale +
HA k3s server install + hello-world workload.

Applied to `hosts: k3s` by `ansible/k3s-up.yml`.

Imports: [[common]], [[tailscale]], [[k3s]], [[k3s-hello]].

No `docker` or `registry-login` imports — the cluster nodes don't run
docker-compose (k3s ships its own containerd). They also don't pull from
GHCR for the hello workload (`nginxdemos/hello` is on Docker Hub, public),
so no registry auth needed.
