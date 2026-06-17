FROM node:22-bookworm-slim AS builder

WORKDIR /app

COPY ui-react/package.json ui-react/package-lock.json* ./
RUN npm ci

COPY ui-react/ ./
RUN npm run build

FROM nginx:alpine

COPY --from=builder /app/dist /usr/share/nginx/html
COPY ui-react/nginx.conf /etc/nginx/conf.d/default.conf
COPY ui-react/docker-entrypoint.d/40-runtime-config.sh /docker-entrypoint.d/40-runtime-config.sh
RUN chmod +x /docker-entrypoint.d/40-runtime-config.sh

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
