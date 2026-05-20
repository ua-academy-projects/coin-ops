# vm-ui-stack

Full lifecycle (system prep + docker install + registry login + service
deploy) for a VM-mode UI node — React SPA + nginx gateway with optional
TLS termination.

Applied to `hosts: ui` by `deploy.yml`.

Imports: [[common]], [[docker]], [[registry-login]], [[ui]].
