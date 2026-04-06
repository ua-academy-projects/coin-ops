# Frontend Role

Deploys the Python Flask web application acting as the client-facing UI for the CoinOps project. Also provisions a local Redis instance serving as an ephemeral UI-state store. Targeted at `vm1`.

## Tasks
1. Installs `python3`, `python3-venv`, and **Redis** (`redis-server`), which is required for UI State Storage caching.
2. Prepares a virtual environment (`venv`) and executes `pip install` from `requirements.txt`.
3. Generates the `frontend.env` configuration file mapping service-to-service URLs and local Redis credentials.
4. Activates and restarts both `frontend.service` and `redis-server`.

## Role Variables
Expects the following variables from `group_vars/all/vars.yml`:
- `proxy_url` — external route to fetch live rates (`vm2`).
- `history_api_url` — external route to fetch analytics (`vm3`).
- `redis_url` — strict local binding loopback `redis://127.0.0.1:6379/0`.

## Dependencies
Requires a local instance of `redis-server` (installed locally by this role). Requires endpoints exposed by `proxy` and `history_service` to render populated UI frames.
