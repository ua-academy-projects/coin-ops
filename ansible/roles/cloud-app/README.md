# cloud-app

Deploy the application stack (proxy + history-api + history-consumer + UI nginx)
on a cloud app VM via docker-compose. The VM sits behind the cloud's HTTPS
load balancer, which terminates TLS and forwards plain HTTP on `:80`.

**Where it runs:** on every host in the `app` inventory group.

**Reads:** its own `defaults/main.yml` (config from `config/lab.yaml` ->
`coinops_*`, with env fallbacks) plus the secrets published by the
[[cloud-secrets]] role (`coinops_db_password`, `coinops_ghcr_token`).

**Produces:** `/etc/cognitor/cloud-app.env`, `/opt/cognitor/cloud-app/nginx.conf`,
`/opt/cognitor/cloud-app/compose.yaml`, then a running compose stack listening
on `:80`. Health-checks `http://localhost/health` before declaring success.
