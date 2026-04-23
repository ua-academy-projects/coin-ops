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
npm run test          # vitest — catches logic/rendering issues
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
pytest tests/                          # run unit tests
```

If you add new `.py` files, include them in the `py_compile` step.

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
- Run the PostgreSQL integration tests if you changed the `runtime/` schema or queue logic:
  ```bash
  psql -d coin_ops -f runtime/00_run_all.sql
  psql -d coin_ops -f runtime/tests/test_runtime.sql
  ```
- If the change alters the data flow between services (proxy → queue →
  consumer → API → UI), it should be exercised through the local deployment
  workflow or the full VM environment before merging.

---

## When Local Checks Are Enough

Local verification is sufficient for:

- Pure UI changes (styling, component logic, new pages) — lint + build + dev server.
- Isolated Go proxy changes (new endpoint, caching tweak) — test + build.
- Isolated Python changes (new history endpoint, consumer logic) — ruff + py_compile.
- Documentation-only changes — no service checks needed.
- Dockerfile changes that don't alter runtime behavior — docker build.

## When You Still Need VM / Full-Environment Testing

Escalate to the full VM-based deployment (`terraform` + `ansible`) when:

- Your change alters **inter-service communication** (API contracts, queue
  message format, nginx routing).
- You modify **TLS, domain, or networking** configuration (`APP_DOMAIN`,
  `TLS_MODE`, port mappings, UFW rules).
- You change **Ansible playbooks or Terraform resources** that affect VM
  provisioning or service orchestration.
- You modify the **database schema** (`history/schema.sql`,
  `runtime/*.sql`) — verify that migrations apply cleanly against a real
  PostgreSQL instance.
- You switch or extend the **runtime backend** (`RUNTIME_BACKEND`) or wire
  new `runtime/` assets into the deployment.

If in doubt, mention in your PR description that the change would benefit
from environment-level verification, and the reviewer can coordinate testing.
