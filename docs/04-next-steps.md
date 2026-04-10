# Next Steps

## Infrastructure

- **Docker Swarm** — deploy containers across all 5 VMs instead of one machine
  - server1 as Swarm manager
  - server2, server3, server4 as workers
  - Same docker-compose.yml, different command: `docker stack deploy`

- **Nginx on server1** — proper reverse proxy in front of Flask dev server
  - Single entry point for browser
  - Flask and proxy stay internal
  - Foundation for HTTPS

- **Gunicorn** — replace Flask dev server with production-grade Python web server

- **HTTPS** — SSL certificates, remove "Not secure" browser warning

## Automation

- **GitHub Actions CI/CD** — auto-deploy when code is pushed to GitHub
- **Ansible Vault** — encrypt passwords and secrets in playbooks
- **Git-based deployment** — Ansible pulls code from GitHub instead of copying files

## Monitoring

- **Prometheus + Grafana** — real infrastructure monitoring and alerting

## Future Iterations

- **Kubernetes** — orchestrate containers at scale
- **Helm charts** — package Kubernetes deployments
