# Contributing Guidelines

## Branch Policy

- Base branch: `dev`
- Create feature branches from `dev`
- Open pull requests back into `dev`
- Use squash merge for feature branches

Example:

```bash
git checkout dev
git checkout -b feature/your-change
git push origin feature/your-change
```

## Commit Messages

Use concise semantic commit messages:

- `feat: add market filter`
- `fix: handle empty whale response`
- `docs: update k3s runbook`
- `chore: clean obsolete deployment files`

## Local Checks

Run checks for the service you touched before opening a PR.

### Frontend

```bash
cd ui-react
npm ci
npm run lint
npm run build
npm run test:run --if-present
```

### Go Proxy

```bash
cd proxy
go test ./...
go build ./...
```

### Python History

```bash
cd history
python -m pip install -r requirements.txt -r requirements-dev.txt ruff
ruff check .
python -m py_compile main.py consumer.py
```

Python tests from repository root:

```bash
python -m pytest tests/python/unit -v
python -m pytest tests/python/integration -v
```

### Docker Images

Run these if you changed Dockerfiles or image dependencies:

```bash
docker build -t coin-ops/proxy ./proxy
docker build -t coin-ops/history-api -f ./history/Dockerfile.api ./history
docker build -t coin-ops/history-consumer -f ./history/Dockerfile.consumer ./history
docker build -t coin-ops/ui ./ui-react
```

### Ansible / Kubernetes

For Ansible changes:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --syntax-check
```

When practical, run the changed layer with tags:

```bash
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags ingress
```

## CI

Pull requests into `dev` run GitHub Actions checks for:

- frontend lint/test/build
- Go test/build
- Python lint/syntax/unit/integration tests
- Docker image builds

## Deployment Notes

Current deployment is Kubernetes-only inside this repository:

- k3s cluster automation lives in `ansible/k3s-cluster.yml`
- platform components live in `ansible/k3s-platform.yml`
- CoinOps app deployment lives in `ansible/coinops-app.yml`

The GCP VM infrastructure is managed by the separate `gcp-terraform-bootstrap`
repository.

## Security

Never commit real credentials.

Do not commit:

- kubeconfig files
- Headlamp tokens
- GHCR tokens
- Cloudflare API tokens
- SSH private keys
- GCP service account JSON files
- `.env` files with real values

Secrets used by the k3s deployment must come from GCP Secret Manager and be
projected into Kubernetes Secrets by Ansible.
