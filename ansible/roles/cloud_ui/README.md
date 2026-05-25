# cloud_ui
Deploy the UI-only stack on a cloud VM that lives separately from the
backend nodes. Used when the UI is split off to its own cloud
(`domain.ui.cloud` differs from `domain.api.cloud` in `lab.yaml`); when
the UI shares the backend VMs the [[cloud_app]] role renders the full
compose file instead.

**Where it runs:** every host in the `ui` inventory group.

**Reads:** `ui_image`, `ui_proxy_url`, `ui_history_url` from this role's
`defaults/main.yml` (config from `config/lab.yaml` -> `coinops_*`).

**Produces:** `/opt/cognitor/cloud-ui/compose.yaml`, a running UI
container on `:80`, health-checked at `http://localhost/health`.
