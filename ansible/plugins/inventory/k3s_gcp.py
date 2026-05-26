#!/usr/bin/env python3
# =============================================================================
# ansible/inventory/k3s_gcp.py
# =============================================================================
# Ansible Dynamic Inventory for the k3s HA cluster on GCP.
#
# This script:
#   1. Reads configs/compute.json and configs/cluster.json (source of truth)
#   2. Queries GCP Compute Engine for live instance IPs (via gcloud SDK or
#      the GCP Compute API) matching the node names defined in compute.json
#   3. Fetches the SSH private key from GCP Secret Manager
#   4. Emits an Ansible-compatible JSON inventory
#
# Groups produced:
#   k3s_cluster       — all k3s VMs (bastion + nodes)
#   k3s_bastion       — the Bastion Host (public IP, SSH jump host)
#   k3s_control_plane — all 3 control-plane nodes
#   k3s_init_node     — the --cluster-init bootstrap leader (node-0)
#   k3s_join_nodes    — nodes that join as server peers (node-1, node-2)
#
# Usage:
#   # List inventory (human-readable)
#   ansible-inventory -i ansible/inventory/k3s_gcp.py --list
#
#   # Ping all k3s nodes (via Bastion jump)
#   ansible k3s_control_plane -i ansible/inventory/k3s_gcp.py -m ping
#
#   # Run a playbook
#   ansible-playbook -i ansible/inventory/k3s_gcp.py ansible/playbooks/validate.yml
#
# Requirements:
#   pip install google-cloud-compute google-cloud-secret-manager
#
# Authentication:
#   Uses Application Default Credentials (ADC):
#     gcloud auth application-default login
#   Or set GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa-key.json
#
# Configuration (env vars or configs/cluster.json):
#   K3S_GCP_PROJECT   — GCP project ID (overrides cluster.json)
#   K3S_GCP_REGION    — GCP region     (overrides cluster.json)
#   K3S_CONFIG_DIR    — path to the configs/ directory
#                       (default: <this script's dir>/../../terraform/k3s/configs)
# =============================================================================

from __future__ import annotations

import json
import os
import sys
import argparse
import subprocess
from pathlib import Path
from typing import Any


# ─── Config paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
# Default: walk up to find configs/ relative to this script
DEFAULT_CONFIGS_DIR = SCRIPT_DIR.parent.parent / "terraform" / "k3s" / "configs"
CONFIGS_DIR = Path(os.environ.get("K3S_CONFIG_DIR", DEFAULT_CONFIGS_DIR))


def load_configs() -> tuple[dict, dict, dict]:
    """Load all k3s JSON config files."""
    cluster_cfg    = json.loads((CONFIGS_DIR / "cluster.json").read_text())
    compute_cfg    = json.loads((CONFIGS_DIR / "compute.json").read_text())
    networking_cfg = json.loads((CONFIGS_DIR / "networking.json").read_text())
    return cluster_cfg, compute_cfg, networking_cfg


def load_mappings() -> dict:
    """Load the shared cloud mappings table from the parent configs/ dir."""
    mappings_path = CONFIGS_DIR.parent.parent / "configs" / "mappings.json"
    if mappings_path.exists():
        return json.loads(mappings_path.read_text())
    # Fallback: inline the GCP-relevant subset
    return {
        "instance_type_map": {
            "micro":      {"gcp": "e2-micro"},
            "small":      {"gcp": "e2-small"},
            "medium":     {"gcp": "e2-medium"},
            "standard-2": {"gcp": "e2-standard-2"},
            "large":      {"gcp": "e2-standard-4"},
        },
        "image_map": {
            "debian-12": {"gcp": "debian-cloud/debian-12"},
            "ubuntu-22": {"gcp": "ubuntu-os-cloud/ubuntu-2204-lts"},
        },
        "zone_map": {
            "us-central-a": {"gcp": "us-central1-a"},
            "us-central-b": {"gcp": "us-central1-b"},
            "us-central-c": {"gcp": "us-central1-c"},
        },
        "region_map": {
            "us-central1": {"gcp": "us-central1"},
        },
    }


def get_project_and_region(cluster_cfg: dict) -> tuple[str, str]:
    """Resolve project/region from env overrides or cluster.json."""
    project = os.environ.get("K3S_GCP_PROJECT") or cluster_cfg["project_id"]
    region  = os.environ.get("K3S_GCP_REGION")  or cluster_cfg["region"]
    return project, region


def get_instance_ip(instance_name: str, zone: str, project: str) -> str | None:
    """
    Query the live internal IP of a GCP instance via gcloud CLI.
    Falls back to None if the instance doesn't exist yet.
    """
    try:
        result = subprocess.run(
            [
                "gcloud", "compute", "instances", "describe", instance_name,
                f"--zone={zone}",
                f"--project={project}",
                "--format=get(networkInterfaces[0].networkIP)",
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        ip = result.stdout.strip()
        return ip if ip else None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def get_bastion_external_ip(instance_name: str, zone: str, project: str) -> str | None:
    """Query the live external IP of the Bastion Host."""
    try:
        result = subprocess.run(
            [
                "gcloud", "compute", "instances", "describe", instance_name,
                f"--zone={zone}",
                f"--project={project}",
                "--format=get(networkInterfaces[0].accessConfigs[0].natIP)",
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        ip = result.stdout.strip()
        return ip if ip else None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def get_ssh_key_from_secret_manager(project: str, secret_id: str = "k3s-ssh-private-key") -> str | None:
    """
    Fetch the SSH private key from GCP Secret Manager.
    Returns the key content or None if unavailable.
    Writes it to a temp file and returns the path.
    """
    key_path = Path.home() / ".ssh" / "k3s_id_rsa"
    if key_path.exists():
        return str(key_path)  # already cached

    try:
        result = subprocess.run(
            [
                "gcloud", "secrets", "versions", "access", "latest",
                f"--secret={secret_id}",
                f"--project={project}",
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode == 0 and result.stdout.strip():
            key_path.parent.mkdir(parents=True, exist_ok=True)
            key_path.write_text(result.stdout)
            key_path.chmod(0o600)
            return str(key_path)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


def build_inventory(
    cluster_cfg: dict,
    compute_cfg: dict,
    mappings: dict,
    project: str,
    region: str,
) -> dict[str, Any]:
    """
    Build the complete Ansible inventory JSON structure.

    Inventory format:
    {
      "_meta": { "hostvars": { "<hostname>": { ... } } },
      "all":   { "children": [...] },
      "k3s_cluster":       { "hosts": [...] },
      "k3s_bastion":       { "hosts": ["k3s-bastion"] },
      "k3s_control_plane": { "hosts": ["k3s-node-0", "k3s-node-1", "k3s-node-2"] },
      "k3s_init_node":     { "hosts": ["k3s-node-0"] },
      "k3s_join_nodes":    { "hosts": ["k3s-node-1", "k3s-node-2"] },
    }
    """
    inventory: dict[str, Any] = {
        "_meta": {"hostvars": {}},
        "all": {"children": ["k3s_cluster"]},
        "k3s_cluster":       {"hosts": [], "vars": {"k3s_version": cluster_cfg.get("k3s_version", "v1.30.2+k3s2")}},
        "k3s_bastion":       {"hosts": []},
        "k3s_control_plane": {"hosts": []},
        "k3s_init_node":     {"hosts": []},
        "k3s_join_nodes":    {"hosts": []},
    }

    # ── Fetch SSH key path ──────────────────────────────────────────────────
    ssh_key_path = get_ssh_key_from_secret_manager(project)

    # ── Bastion Host ──────────────────────────────────────────────────────
    bastion_cfg  = compute_cfg["bastion"]
    bastion_zone = mappings["zone_map"][bastion_cfg["zone"]]["gcp"]
    bastion_name = "k3s-bastion"
    bastion_ip   = get_bastion_external_ip(bastion_name, bastion_zone, project)

    if bastion_ip:
        inventory["_meta"]["hostvars"][bastion_name] = {
            "ansible_host":                 bastion_ip,
            "ansible_user":                 "ubuntu",
            "ansible_ssh_private_key_file": ssh_key_path,
            "ansible_ssh_common_args":      "-o StrictHostKeyChecking=no",
            # Metadata from compute.json
            "gcp_zone":     bastion_zone,
            "gcp_project":  project,
            "role":         "bastion",
            "k3s_role":     "none",
            "public_ip":    bastion_ip,
        }
        inventory["k3s_bastion"]["hosts"].append(bastion_name)
        inventory["k3s_cluster"]["hosts"].append(bastion_name)

    # ── k3s Control-Plane Nodes ──────────────────────────────────────────
    for node in compute_cfg["nodes"]:
        node_name = node["name"]
        node_zone = mappings["zone_map"][node["zone"]]["gcp"]
        node_ip   = get_instance_ip(node_name, node_zone, project)

        # ProxyJump through Bastion for all private nodes
        proxy_args = (
            f"-o StrictHostKeyChecking=no "
            f"-o ProxyJump=ubuntu@{bastion_ip}"
            if bastion_ip else "-o StrictHostKeyChecking=no"
        )

        hostvars: dict[str, Any] = {
            "ansible_host":                 node_ip or node_name,  # fallback to name
            "ansible_user":                 "ubuntu",
            "ansible_ssh_private_key_file": ssh_key_path,
            "ansible_ssh_common_args":      proxy_args,
            # Metadata from compute.json (available as Ansible variables in playbooks)
            "gcp_zone":         node_zone,
            "gcp_project":      project,
            "role":             "k3s-control-plane",
            "k3s_role":         node["k3s_role"],      # "init" or "server"
            "node_index":       compute_cfg["nodes"].index(node),
            "disk_size_gb":     node["disk_size_gb"],
            "instance_size":    node["instance_size"],
            "network_tags":     node["network_tags"],
        }
        inventory["_meta"]["hostvars"][node_name] = hostvars

        # Assign to groups based on ansible_groups in compute.json
        for group in node.get("ansible_groups", []):
            if group not in inventory:
                inventory[group] = {"hosts": []}
            if node_name not in inventory[group]["hosts"]:
                inventory[group]["hosts"].append(node_name)

        inventory["k3s_control_plane"]["hosts"].append(node_name)
        inventory["k3s_cluster"]["hosts"].append(node_name)

    return inventory


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Ansible dynamic inventory for k3s HA cluster on GCP"
    )
    parser.add_argument("--list", action="store_true", help="List all inventory")
    parser.add_argument("--host", metavar="HOST",     help="Get vars for a specific host")
    args = parser.parse_args()

    cluster_cfg, compute_cfg, networking_cfg = load_configs()
    mappings = load_mappings()
    project, region = get_project_and_region(cluster_cfg)

    if args.host:
        # Return hostvars for a single host
        inventory = build_inventory(cluster_cfg, compute_cfg, mappings, project, region)
        hostvars  = inventory["_meta"]["hostvars"].get(args.host, {})
        print(json.dumps(hostvars, indent=2))
        return

    # Default: --list
    inventory = build_inventory(cluster_cfg, compute_cfg, mappings, project, region)
    print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
