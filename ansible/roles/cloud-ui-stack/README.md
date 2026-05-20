# cloud-ui-stack

Full lifecycle (system prep + docker install + registry login + UI
deploy) for a cloud UI-only VM behind the cloud's HTTPS load balancer.

Applied to `hosts: ui` by `cloud-deploy.yml` when the deploy is split
across clouds.

Imports: [[common]], [[docker]], [[registry-login]], [[cloud-ui]].
