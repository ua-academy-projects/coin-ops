# Repository Guidelines

## Project Structure & Module Organization

This repo is a distributed Polymarket dashboard. `ui-react/` contains the main React/Vite UI. `proxy/` contains the Go live-data proxy. `history/` contains the FastAPI history API, RabbitMQ consumer, and PostgreSQL schema. `runtime/` contains PostgreSQL queue assets for the target runtime backend. `ansible/` and `terraform/` own VM provisioning and deployment. `deploy/compose/` contains per-node Docker Compose stacks. Supporting docs live in `docs/`.

## Build, Test, and Development Commands

Always run relevant checks before committing. Use `make verify` for all services or target specific ones.

Frontend (`ui-react/`):
```bash
cd ui-react
npm ci
npm run lint      # TypeScript no-emit check
npm run test      # Vitest unit tests
npm run build     # production build
```

Go proxy (`proxy/`):
```bash
cd proxy
make build        # Linux amd64 binary
make run          # local go run
go test ./...     # unit tests
```

Python history services (`history/`):
```bash
cd history
pip install -r requirements.txt
python -m py_compile main.py consumer.py   # syntax check
pytest               # unit tests
```

Full stack (Docker Compose):
```bash
make local-up        # build and start all services
make local-down      # stop services
make local-logs      # follow logs
./smoke/smoke.sh     # end-to-end smoke tests
```

Infrastructure:
```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

## Coding Style & Naming Conventions

Use TypeScript for React UI code and keep components in `ui-react/src/`. Prefer existing Tailwind and glass-dashboard conventions. Go code should follow `gofmt` and small, explicit functions. Python code should use clear snake_case names and keep service responsibilities separated between `main.py` and `consumer.py`. YAML files should use two-space indentation. Environment vars in UPPER_SNAKE_CASE.

## Testing Guidelines

Run `make verify` or service-specific checks before PRs. For database changes, run integration tests: `pip install -r history/requirements-dev.txt && python -m pytest tests/python/integration -v`. Use `./smoke/smoke.sh` for end-to-end verification.

## Commit & Pull Request Guidelines

Use concise, imperative commit messages (e.g., `feat: add market chart`). Base branches on `dev`. Require review before merge. Use Squash and Merge.

## Security & Configuration Tips

Never commit real credentials. Use `.env` files and Ansible variables for secrets. Be careful with container networking: inside containers, `localhost` means the container itself. Clean Windows line endings from .env files with `tr -d '\r'`. Support for `RUNTIME_BACKEND=external|postgres` toggle (default external uses RabbitMQ/Redis; postgres uses PostgreSQL queue).

## Architecture Notes

See [docs/architecture.md](docs/architecture.md) for current deployed architecture and [docs/runtime-queue-architecture.md](docs/runtime-queue-architecture.md) for target PostgreSQL runtime. Terraform creates VMs, Ansible configures them, Docker packages services. Node-03 is the browser-facing gateway; keep frontend URLs same-origin for nginx reverse-proxy.

Container images built by GitHub Actions and pushed to GHCR. Use `shabat-latest` for dev, `vX.Y.Z` for releases. TLS controlled by `APP_DOMAIN` and `TLS_MODE`.
