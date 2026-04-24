# Contributing Guidelines

## Branch Policy
- **Base Branch:** `dev`. All development must be based on the `dev` branch.
- Please create a separate feature-branch from `dev`, commit your changes to it, and then open a Pull Request into `dev`.
  
  *Example:*
  ```bash
  git checkout dev
  git checkout -b feature/your-change
  # ... make your changes and commit them
  git push origin feature/your-change
  ```

## Pull Request Rules
- **Required Reviewers:** PRs require review from at least one Core Reviewer before merging.
- **Merge Cadence:** Changes from `dev` are merged to `main` weekly by the mentor.
- **Commit Messages:** Follow standard semantic commit messages (e.g. `feat:`, `chore:`, `fix:`, `docs:`, `refactor:`).
- **Merge Rules:** Use **Squash and Merge** when merging feature branches to keep the history clean.

---

## Before You Open a PR — Local Verification Checklist

Run the checks below **for every service you touched** before pushing your PR.
These mirror what CI runs in `.github/workflows/pr-checks.yml`, so catching
failures locally saves a round-trip.

**Quick start:** from the repo root, run `make verify` to execute all
service checks at once, or target a single service with `make verify-ui`,
`make verify-proxy`, or `make verify-history`.

### Frontend (`ui-react/`)

Run these if you changed anything under `ui-react/`:

```bash
cd ui-react
npm ci                # clean install (or npm install if no lockfile changes)
npm run lint          # tsc --noEmit — catches type errors
npm run build         # production Vite build — catches import/bundling issues
```

A successful `build` is the minimum bar. If your change affects visual
behavior, open `npm run dev` and verify the affected page in the browser.

### Go Proxy (`proxy/`)

Run these if you changed anything under `proxy/`:

```bash
cd proxy
go test ./...         # unit tests
go build ./...        # compilation check
```

Both commands must exit cleanly. `go vet ./...` is also recommended for
catching subtle bugs, but is not currently enforced by CI.

### Python / History (`history/`)

Run these if you changed anything under `history/`:

```bash
cd history
pip install -r requirements.txt ruff   # ensure deps + linter are available
ruff check .                           # lint (default Ruff rules, no local config)
python -m py_compile main.py consumer.py   # syntax verification
```

If you add new `.py` files, include them in the `py_compile` step.

If you changed history read/write database behavior, also run PostgreSQL-backed integration tests:

```bash
cd ..
pip install -r history/requirements-dev.txt
python -m pytest tests/python/integration -v
```

These integration tests use an ephemeral PostgreSQL container (Docker required) and are intentionally separate from the fast unit suite.
They bootstrap both `history/schema.sql` and `runtime/00_run_all.sql`, then exercise `history/main.py` plus the queue-side PostgreSQL consumer in `runtime/runtime_consumer.py`.

Use `psql "$DATABASE_URL" -f runtime/tests/test_runtime.sql` separately when you need the broader runtime smoke coverage, including cache/session `pg_cron` behavior.

### Docker Images

Run these if you changed a Dockerfile, service dependencies, or the build
context of any image:

```bash
docker build -t coin-ops/proxy         ./proxy
docker build -t coin-ops/history-api   -f ./history/Dockerfile.api      ./history
docker build -t coin-ops/history-consumer -f ./history/Dockerfile.consumer ./history
docker build -t coin-ops/ui            ./ui-react
```

You only need to build images for services you changed. A clean build with
no errors is sufficient — you don't have to push or run the image.

### Deployment / Infrastructure (`ansible/`, `terraform/`, `deploy/`)

- Review changed YAML/HCL files for syntax and indentation.
- For Ansible changes, dry-run when practical: `ansible-playbook --check ...`
- For Compose template changes (`deploy/compose/`), verify that Jinja
  placeholders are correct and the YAML is valid after rendering.

### Cross-Service or Runtime Changes (`runtime/`)

If your change spans multiple services or touches the `runtime/` directory:

- Make sure **all** affected service checks above pass.
- If the change alters the data flow between services (proxy → queue →
  consumer → API → UI), it should be exercised through the local deployment
  workflow or the full VM environment before merging.

---

## CI PR Gating Rules

Pull Requests targeting the `dev` branch are automatically checked by GitHub Actions (`.github/workflows/pr-checks.yml`). 
The following **fast test suites** run automatically on every pull request and must pass before merging:

- **Frontend (`ui-react`)**: Unit/component tests (`npm run test`), lint rules, and builds.
- **Go Proxy (`proxy`)**: Go unit tests (`go test ./...`) and builds.
- **Python History (`history`)**: Python syntax validation, linting (`ruff`), and unit tests (`pytest tests/python/unit`).
- **PostgreSQL Integration Tests**: We also automatically run Python integration tests (`pytest tests/python/integration`) on PRs, as they bootstrap quickly thanks to ephemeral Testcontainers PostgreSQL databases.

## When You Still Need Heavier Smoke Checks

The following validation checks are **too heavy for standard PR gating** or require complex deployment configurations. They remain manual or part of staging workflows rather than blocking PR merges:

- **Full VM-based deployments** (`terraform` + `ansible`): Spinning up virtual machines, setting up Nginx, UFW, or SSL certs.
- **Inter-service routing tests**: Testing real HTTP/WebSocket traffic traversing through the Go proxy into the History API over production network layers.
- **End-to-End Runtime DB testing**: Running `runtime/tests/test_runtime.sql` against a live DB, which requires deeper verification of the `pg_cron` subsystem, cache eviction rates, and continuous session tracking.
- **External Integration Checks**: Anything requiring secrets, third-party wallet nodes, APIs, or physical blockchain node syncs.

If your change spans multiple services, alters routing contracts, or modifies `pg_cron` jobs in `runtime/*.sql`, coordinate with reviewers to deploy and smoke-test your branch in a staging environment before finalizing the PR.
