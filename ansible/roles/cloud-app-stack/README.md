# cloud-app-stack

Full lifecycle (system prep + docker install + registry login + managed-DB
schema bootstrap + app deploy) for a cloud app VM behind the cloud's HTTPS
load balancer.

Applied to `hosts: app` by `cloud-deploy.yml` after a preceding
`hosts: localhost` play has run [[cloud-secrets]] to publish resolved
secrets onto cloud hosts.

Imports: [[common]], [[docker]], [[registry-login]],
[[cloud-db-bootstrap]] (no-op unless cloud-native), [[cloud-app]].
