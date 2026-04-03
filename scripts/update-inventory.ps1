# scripts/update-inventory.ps1
#
# Reads current VM IPs from Hyper-V and writes them into ansible/inventory.
# Run this once after every Windows reboot before running Ansible.
#
# Usage (PowerShell as Administrator):
#   cd F:\univ\softserv-internship
#   .\scripts\update-inventory.ps1

$VMs = @{
    "softserve-node-01" = "history"
    "softserve-node-02" = "proxy"
    "softserve-node-03" = "ui"
}

$resolved = @{}

foreach ($vmName in $VMs.Keys) {
    $adapter = Get-VMNetworkAdapter -VMName $vmName -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Error "VM '$vmName' not found or not running."
        exit 1
    }

    # Pick the first IPv4 address
    $ip = $adapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1

    if (-not $ip) {
        Write-Error "No IPv4 address found for '$vmName'. Is it running and has an IP?"
        exit 1
    }

    $resolved[$vmName] = $ip
    Write-Host "  $vmName -> $ip"
}

$inventoryPath = Join-Path $PSScriptRoot "..\ansible\inventory"

$content = @"
[history]
softserve-node-01 ansible_host=$($resolved["softserve-node-01"])

[proxy]
softserve-node-02 ansible_host=$($resolved["softserve-node-02"])

[ui]
softserve-node-03 ansible_host=$($resolved["softserve-node-03"])
"@

Set-Content -Path $inventoryPath -Value $content -Encoding UTF8
Write-Host ""
Write-Host "ansible/inventory updated."
Write-Host "Now run Ansible from WSL:"
Write-Host "  ansible-playbook -i ansible/inventory ansible/provision.yml"
Write-Host "  ansible-playbook -i ansible/inventory ansible/deploy.yml"
