# UI Service

Flask web application that renders the main price dashboard and history page.

## Responsibility

- shows the current selected coin price
- renders historical records table
- requests chart data from the history service
- stores user session state in Redis

## Runtime

- language: Python 3
- framework: Flask
- service port: `5000`
- host VM: `devops-ui`

## Endpoints

- `GET /` - main dashboard
- `GET /history` - historical price table with filters
- `GET /api/chart-data` - chart data for frontend updates

## Dependencies

- Redis for Flask session storage
- Proxy service for live prices
- History service for historical records and chart data

## Environment Variables

- `REDIS_HOST`
- `REDIS_PORT`
- `PROXY_HOST`
- `HISTORY_HOST`
- `SECRET_KEY`

These variables are rendered by Ansible into `ui.service`.

## Systemd

Unit template:

- `ansible/roles/ui/templates/ui.service.j2`

Useful commands on `devops-ui`:

```bash
sudo systemctl status ui
sudo journalctl -u ui.service -n 50
sudo systemctl cat ui.service
sudo systemctl show ui.service -p Environment
```

## Common Problems

### `REDIS_PORT` is `None`

Cause:

- the rendered `ui.service` does not contain `Environment=REDIS_PORT=6379`

Check:

```bash
sudo systemctl cat ui.service
```

### HTTP 500 on `/`

Cause:

- Redis is unavailable
- history service is unavailable
- proxy service is unavailable

Check:

```bash
sudo journalctl -u ui.service -n 50
```

## Notes

- this service uses Flask's built-in server, which is fine for this lab but not for production
- `SECRET_KEY` can be a simple stable value in development, for example `dev-secret`
