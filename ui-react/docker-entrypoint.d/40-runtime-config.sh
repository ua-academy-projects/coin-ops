#!/bin/sh
set -eu

cat > /usr/share/nginx/html/config.js <<EOF
window.__COIN_OPS_CONFIG__ = {
  proxyUrl: "${PROXY_URL:-http://172.31.1.11:8080}",
  historyUrl: "${HISTORY_URL:-http://172.31.1.10:8000}"
};
EOF
