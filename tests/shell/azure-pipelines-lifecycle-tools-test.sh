#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
runner="$repo_root/.azure-pipelines/templates/run-lab-action.yml"
installer="$repo_root/.azure-pipelines/templates/install-lab-tools.yml"

grep -Fq 'installAnsible: ${{ or(eq(parameters.action, '\''deploy'\''), eq(parameters.action, '\''rebuild'\'')) }}' "$runner"
grep -Fq 'name: installAnsible' "$installer"
grep -Fq 'INSTALL_ANSIBLE: ${{ parameters.installAnsible }}' "$installer"

if grep -Fq 'ansible-galaxy collection install -r' "$installer" && ! grep -Fq 'for attempt in 1 2 3' "$installer"; then
  echo "Ansible Galaxy collection downloads are not retried" >&2
  exit 1
fi

grep -Fq -- '--timeout 120' "$installer"
grep -Fq 'if [[ "$INSTALL_ANSIBLE" == "true" ]]' "$installer"

echo "Azure lifecycle installs Ansible only for deploy/rebuild with retries"
