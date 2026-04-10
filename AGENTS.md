# Repository Guidelines

## Project Structure & Module Organization

This repo is a distributed Polymarket dashboard. `ui-react/` contains the main React/Vite UI. `ui/` is the legacy static UI. `proxy/` contains the Go live-data proxy. `history/` contains the FastAPI history API, RabbitMQ consumer, and PostgreSQL schema. `ansible/` and `terraform/` own VM provisioning and deployment. `deploy/compose/` contains per-node Docker Compose stacks. Supporting docs live in `docs/`.

## Build, Test, and Development Commands

Frontend:

```bash
cd ui-react
npm install
npm run dev      # Vite dev server
npm run lint     # TypeScript no-emit check
npm run build    # production build
```

Go proxy:

```bash
cd proxy
make run         # local go run
make build       # Linux amd64 binary
```

Python history services:

```bash
cd history
pip install -r requirements.txt
python main.py       # history API
python consumer.py   # RabbitMQ consumer
```

Infrastructure:

```bash
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

## Coding Style & Naming Conventions

Use TypeScript for React UI code and keep components in `ui-react/src/`. Prefer existing Tailwind and glass-dashboard conventions. Go code should follow `gofmt` and small, explicit functions. Python code should use clear snake_case names and keep service responsibilities separated between `main.py` and `consumer.py`. YAML files should use two-space indentation.

## Testing Guidelines

There is no full automated test suite yet. Minimum verification before committing UI changes is `npm run lint` and `npm run build` in `ui-react/`. For Go changes, run `go test ./...` or `make build` from `proxy/`. For deployment changes, prefer Ansible dry-run/checks where practical and inspect affected Compose files manually.

## Commit & Pull Request Guidelines

Use concise, imperative commit messages, for example `Add top-level project README` or `Simplify market history chart rendering`. Keep unrelated artifacts out of commits. Pull requests should include a short summary, affected services, verification commands, and screenshots for UI changes. Deployment changes should mention whether they affect fresh installs, upgrades, or both.

## Security & Configuration Tips

Never commit real credentials. Use `.env`, Ansible variables, and generated env files for secrets. Keep local VM images, tfstate backups, and Hyper-V artifacts ignored. Be careful with container networking: inside containers, `localhost` means the container itself, not the VM host.

## Architecture Notes

Terraform creates VMs, Ansible configures and deploys them, Docker packages runtime services, RabbitMQ decouples ingestion, PostgreSQL stores history, and Redis stores short-lived UI session state.
