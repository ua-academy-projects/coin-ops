#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="${LOCAL_IMAGE_TAG:-local}"
out_dir="${LOCAL_IMAGE_ARTIFACT_DIR:-$repo_root/.artifacts/images}"

mkdir -p "$out_dir"

docker build -t "coin-ops-proxy:$tag" "$repo_root/proxy"
docker build -t "coin-ops-history-api:$tag" -f "$repo_root/history/Dockerfile.api" "$repo_root/history"
docker build -t "coin-ops-history-consumer:$tag" -f "$repo_root/history/Dockerfile.consumer" "$repo_root/history"
docker build -t "coin-ops-ui:$tag" "$repo_root/ui-react"
docker build -t "coin-ops-postgres-runtime:$tag" -f "$repo_root/deploy/postgres-runtime/Dockerfile" "$repo_root/deploy/postgres-runtime"

docker save "coin-ops-proxy:$tag" -o "$out_dir/proxy.tar"
docker save "coin-ops-history-api:$tag" -o "$out_dir/history-api.tar"
docker save "coin-ops-history-consumer:$tag" -o "$out_dir/history-consumer.tar"
docker save "coin-ops-ui:$tag" -o "$out_dir/ui.tar"
docker save "coin-ops-postgres-runtime:$tag" -o "$out_dir/postgres-runtime.tar"

printf 'Local image archives written to %s\n' "$out_dir"
