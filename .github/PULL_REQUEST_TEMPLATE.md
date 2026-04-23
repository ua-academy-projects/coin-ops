Closes #___

**Release title guidance**
Use a Conventional Commit style PR title when this change can reach `main`:
- `fix: ...` for patch releases
- `feat: ...` for minor releases
- `feat!: ...` or `BREAKING CHANGE:` for major releases

**Change summary**
- 

**Affected services** (delete lines that don't apply)
- [ ] Frontend (`ui-react/`)
- [ ] Go Proxy (`proxy/`)
- [ ] Python / History (`history/`)
- [ ] Runtime (`runtime/`)
- [ ] Infrastructure (`ansible/`, `terraform/`, `deploy/`)
- [ ] Docs only

**Local verification** (check every box that applies — see [CONTRIBUTING.md](../CONTRIBUTING.md#before-you-open-a-pr--local-verification-checklist))
- [ ] `make verify` passes (or ran per-service checks below)
- [ ] Frontend: `npm run lint` + `npm run build` clean
- [ ] Go: `go test ./...` + `go build ./...` clean
- [ ] Python: `ruff check .` + `py_compile` clean
- [ ] Docker: affected image(s) build successfully
- [ ] Verified in browser / dev server (for UI changes)
- [ ] Requires full VM/environment testing (explain below)

**Test plan**
- [ ] 

**Carry-over list**
- 

- [ ] Docs updated
- [ ] Breaking change?
