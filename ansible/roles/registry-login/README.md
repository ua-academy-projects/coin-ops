# registry-login

Authenticate the Docker daemon on the target host against
`{{ image_registry_host }}` using `{{ registry_username }}` /
`{{ registry_token }}`.

Idempotent. No-op when either credential variable is empty (public-image
runs). Used by both VM-mode (`vm-*-stack`) and cloud-mode (`cloud-*-stack`)
meta-roles.

Expected vars come from `group_vars/all/main.yml` — no role-local defaults.
