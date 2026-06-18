#!/bin/sh
set -eu

cat > /usr/share/nginx/html/config.js <<EOF
window.__COIN_OPS_CONFIG__ = {
  proxyUrl: "${PROXY_URL:-/api}",
  historyUrl: "${HISTORY_URL:-/history-api}"
};
EOF

cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location /api/ {
        proxy_pass ${PROXY_UPSTREAM:-http://coin-ops-proxy:8080/};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /history-api/ {
        proxy_pass ${HISTORY_UPSTREAM:-http://coin-ops-history-api:8000/};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        try_files \$uri /index.html;
    }

    location = /health {
        access_log off;
        return 200 '{"status":"ok"}';
        add_header Content-Type application/json;
    }

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    gzip on;
    gzip_types text/html text/css application/javascript application/json;
}
EOF
