#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
lab_sh="$repo_root/terraform/multicloud-vm-yaml-lab/scripts/lab.sh"

grep -Fq 'TAILSCALE_AUTH_KEY=...' "$lab_sh"
grep -Fq 'push_secret_value tailscale_auth_key TAILSCALE_AUTH_KEY tailscale-auth-key false' "$lab_sh"

echo "lab.sh durable secret contract is complete"
