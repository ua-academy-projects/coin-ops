#!/usr/bin/env bash
# scripts/ansible-run.sh
#
# Resolves current Vagrant SSH details and runs ansible-playbook.
# Works regardless of what IP Hyper-V assigned — uses port-forwarding.
#
# Usage:
#   ./scripts/ansible-run.sh ansible/provision.yml
#   ./scripts/ansible-run.sh ansible/deploy.yml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Vagrant may be vagrant.exe when called from WSL
VAGRANT=$(command -v vagrant 2>/dev/null || command -v vagrant.exe 2>/dev/null)
if [ -z "$VAGRANT" ]; then
    echo "ERROR: vagrant not found in PATH"
    exit 1
fi

# Parse one field from `vagrant ssh-config <name>`
ssh_field() {
    local vm_name=$1 field=$2
    (cd "$PROJECT_DIR" && $VAGRANT ssh-config "$vm_name" 2>/dev/null) \
        | grep "^\s*${field} " | awk '{print $2}'
}

echo "Resolving Vagrant SSH configs..."

resolve_vm() {
    local name=$1
    local host port key
    host=$(ssh_field "$name" HostName)
    port=$(ssh_field "$name" Port)
    key=$(ssh_field "$name" IdentityFile)

    if [ -z "$host" ]; then
        echo "ERROR: could not resolve SSH config for $name — is it running?" >&2
        exit 1
    fi

    echo "  $name  →  $host:$port"
    printf "%s ansible_host=%s ansible_port=%s ansible_ssh_private_key_file=%s" \
        "$name" "$host" "$port" "$key"
}

INVENTORY=$(mktemp /tmp/coin-ops-inventory.XXXXXX)
trap "rm -f $INVENTORY" EXIT

{
    echo "[history]"
    resolve_vm softserve-node-01

    echo ""
    echo "[proxy]"
    resolve_vm softserve-node-02

    echo ""
    echo "[ui]"
    resolve_vm softserve-node-03

    echo ""
    echo "[all:vars]"
    echo "ansible_user=vagrant"
    echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
} >> "$INVENTORY"

echo ""
echo "Running: ansible-playbook $*"
echo ""

ansible-playbook -i "$INVENTORY" "$@"
