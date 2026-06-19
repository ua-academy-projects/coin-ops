# Contributing

This repository is infrastructure-only. The application is deployed from existing GHCR images; do not add app source, local app build steps, or smoke stacks back into this repo.

## Before Opening a PR

Run the full local equivalent of GitHub validation:

```bash
cd /home/notebook/projects/coin-ops
make ci-validate
```

Use `make terraform-fmt` before committing when Terraform formatting fails.
The validation wrapper initializes without the remote backend and avoids
depending on live AWS credentials.

If you changed `deploy/postgres-runtime/`, also run:

```bash
docker build -t coin-ops-postgres-runtime -f deploy/postgres-runtime/Dockerfile deploy/postgres-runtime
```

If you changed Compose templates, render them through the owning Ansible role or validate the rendered file on a target host with `docker compose config -q`.

## Infrastructure Areas

- `terraform/`: cloud resources, EKS/Jenkins, remote-state bootstrap scripts, generated local metadata, Cloudflare, observability, and multicloud networking.
- `ansible/`: active EKS workloads plus legacy host, VM Compose, and k3s roles.
- `deploy/compose/`: Jinja-rendered VM Compose templates. Do not run these raw.
- `deploy/sql/`: retained PostgreSQL schema/runtime bootstrap SQL used by VM Compose and k3s CNPG deployments.
- `deploy/postgres-runtime/`: PostgreSQL 16 image with `pg_cron` and `pgmq` support.
- `docs/`: admin documentation.

## PR Expectations

Use a Conventional Commit style PR title when the change may reach `main`. Keep PRs scoped. Include:

- summary of changed infrastructure behavior
- affected clouds/playbooks/roles
- verification commands and results
- whether the change affects fresh installs, upgrades, or both
- any manual live-environment validation still needed

## Notes

`RUNTIME_BACKEND=external` remains rollback support. The normal path is PostgreSQL runtime mode. Application images are deployment inputs, not build outputs of this repository.
