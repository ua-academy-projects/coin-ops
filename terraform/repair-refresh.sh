#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash repair-refresh.sh --enabled gcp plan
  bash repair-refresh.sh --enabled gcp apply

Runs refresh-only from an isolated temporary Terraform copy for state repair.
It can narrow enabled clouds, disables secret-version reads, and stubs disabled
Azure wiring so broken or partially deleted resources do not block refresh.

Use "plan" first. Use "apply" only after reviewing the refresh-only diff.
EOF
}

if [[ "${1:-}" != "--enabled" || -z "${2:-}" || -z "${3:-}" ]]; then
  usage
  exit 1
fi

ENABLED_CLOUDS_RAW="$2"
ACTION="$3"
shift 3

if [[ "${ACTION}" != "plan" && "${ACTION}" != "apply" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/coinops-repair-refresh.XXXXXX")"
TMP_TERRAFORM_DIR="${TMP_ROOT}/terraform"

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TMP_TERRAFORM_DIR}"
cp -a "${TERRAFORM_DIR}/." "${TMP_TERRAFORM_DIR}/"
rm -rf "${TMP_TERRAFORM_DIR}/.terraform"

python3 - <<'PY' "${TMP_TERRAFORM_DIR}" "${ENABLED_CLOUDS_RAW}"
import json
import pathlib
import re
import shutil
import sys

terraform_dir = pathlib.Path(sys.argv[1])
enabled_clouds = [cloud.strip() for cloud in sys.argv[2].split(",") if cloud.strip()]
enabled_clouds_set = set(enabled_clouds)

if not enabled_clouds:
    raise SystemExit("At least one enabled cloud is required.")

clouds_path = terraform_dir / "config" / "clouds.json"
clouds_data = json.loads(clouds_path.read_text(encoding="utf-8"))
clouds_data.setdefault("clouds", {})["enabled"] = enabled_clouds
if clouds_data["clouds"].get("control_plane") not in enabled_clouds_set:
    clouds_data["clouds"]["control_plane"] = enabled_clouds[0]
if clouds_data["clouds"].get("secret_backend") not in enabled_clouds_set:
    clouds_data["clouds"]["secret_backend"] = enabled_clouds[0]
clouds_path.write_text(json.dumps(clouds_data, indent=4) + "\n", encoding="utf-8")

locals_path = terraform_dir / "locals.tf"
locals_content = locals_path.read_text(encoding="utf-8")
for name in ("gcp", "aws", "azure"):
    locals_content = re.sub(
        rf"(\s*)read_{name}_secret_backend\s*=.*",
        rf"\1read_{name}_secret_backend = false",
        locals_content,
    )
    locals_content = re.sub(
        rf"(\s*){name}_db_secrets\s*=.*",
        rf"\1{name}_db_secrets  = {{}}",
        locals_content,
    )
    locals_content = re.sub(
        rf"(\s*){name}_app_secrets\s*=.*",
        rf"\1{name}_app_secrets = {{}}",
        locals_content,
    )
locals_path.write_text(locals_content, encoding="utf-8")

gcp_path = terraform_dir / "gcp.tf"
gcp_content = gcp_path.read_text(encoding="utf-8")
gcp_content = gcp_content.replace(
    "next_hop_ip      = module.gcp_instances[0].instance_ips[local.gcp_nat_host_name].private_ip",
    'next_hop_ip      = try(module.gcp_instances[0].instance_ips[local.gcp_nat_host_name].private_ip, "")',
)
gcp_path.write_text(gcp_content, encoding="utf-8")

aws_path = terraform_dir / "aws.tf"
aws_content = aws_path.read_text(encoding="utf-8")
aws_content = aws_content.replace(
    "nat_network_interface_id = module.aws_instances[0].instance_primary_network_interface_ids[local.aws_nat_host_name]",
    'nat_network_interface_id = try(module.aws_instances[0].instance_primary_network_interface_ids[local.aws_nat_host_name], "")',
)
aws_content = aws_content.replace(
    'backend_security_group_id = module.aws_security_groups[0].sg_ids["app-backend"]',
    'backend_security_group_id = try(module.aws_security_groups[0].sg_ids["app-backend"], "")',
)
aws_path.write_text(aws_content, encoding="utf-8")

aws_network_outputs_path = terraform_dir / "modules" / "cloud" / "aws" / "network" / "outputs.tf"
aws_network_outputs = aws_network_outputs_path.read_text(encoding="utf-8")
aws_network_outputs = aws_network_outputs.replace(
    "value       = { for name in keys(local.private_subnets) : name => aws_subnet.subnet[name].id }",
    "value       = { for name, subnet in aws_subnet.subnet : name => subnet.id if contains(keys(local.private_subnets), name) }",
)
aws_network_outputs = aws_network_outputs.replace(
    "value       = [for name in keys(local.private_subnets) : aws_subnet.subnet[name].id]",
    "value       = [for name, subnet in aws_subnet.subnet : subnet.id if contains(keys(local.private_subnets), name)]",
)
aws_network_outputs_path.write_text(aws_network_outputs, encoding="utf-8")

if "azure" not in enabled_clouds_set:
    shutil.rmtree(terraform_dir / "modules" / "cloud" / "azure", ignore_errors=True)

    disabled_module_dir = terraform_dir / "modules" / "cloud" / "disabled"
    disabled_module_dir.mkdir(parents=True, exist_ok=True)
    (disabled_module_dir / "main.tf").write_text("", encoding="utf-8")

    (terraform_dir / "azure.tf").write_text(
        """module "azure_network" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_security_groups" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_instances" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_nat_route" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_database" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_secrets" {
  count  = 0
  source = "./modules/cloud/disabled"
}
""",
        encoding="utf-8",
    )

    providers_path = terraform_dir / "providers.tf"
    providers = providers_path.read_text(encoding="utf-8")
    providers = providers.replace(
        """    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
""",
        "",
    )
    providers = re.sub(
        r"\n\s*azurerm\s*=\s*\{\s*\n\s*source\s*=\s*\"hashicorp/azurerm\"\s*\n\s*version\s*=\s*\"[^\"]+\"\s*\n\s*\}",
        "",
        providers,
        flags=re.MULTILINE,
    )
    providers = re.sub(
        r"\nprovider\s+\"azurerm\"\s*\{\s*(?:features\s*\{\s*\}\s*)?(?:[^\n]*\n)*?\}\s*\n",
        "\n",
        providers,
        flags=re.MULTILINE,
    )
    providers_path.write_text(providers, encoding="utf-8")

    azurerm_refs = [
        str(path.relative_to(terraform_dir))
        for path in terraform_dir.rglob("*.tf")
        if ".terraform" not in path.parts and "azurerm" in path.read_text(encoding="utf-8", errors="ignore")
    ]
    if azurerm_refs:
        raise SystemExit("Azure provider references remain in repair copy: " + ", ".join(azurerm_refs))
PY

cat <<EOF
Prepared isolated Terraform repair copy:
  ${TMP_TERRAFORM_DIR}

Enabled clouds for repair: ${ENABLED_CLOUDS_RAW}
Secret-version data reads are disabled in the temporary copy.
EOF

cd "${TMP_TERRAFORM_DIR}"
terraform init -reconfigure

if [[ "${ACTION}" == "plan" ]]; then
  terraform plan -refresh-only "$@"
else
  terraform apply -refresh-only "$@"
fi
