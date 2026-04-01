# ui

React + Vite frontend for coin-ops.

## Dev

```bash
npm install
npm run dev     # http://localhost:5173
```

## Build

```bash
VITE_API_PROXY_URL=http://<proxy-host>:8000 npm run build
# output: dist/
```

Serve `dist/` with nginx or `python3 -m http.server`.
