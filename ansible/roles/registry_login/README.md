# registry_login
Authenticate the Docker daemon on the target host against
`{{ image_registry_host }}` using `{{ registry_username }}` /
`{{ registry_token }}`.

Idempotent. No-op when either credential variable is empty (public-image
runs). Used by both VM-mode (`vm-*-stack`) and cloud-mode (`cloud-*-stack`)
meta-roles.

Inputs are declared in this role's `defaults/main.yml`: the registry from
`config/lab.yaml` (`app.image_registry` -> `coinops_image_registry`, env
overrides), the token from [[cloud_secrets]] (`coinops_ghcr_token`).
