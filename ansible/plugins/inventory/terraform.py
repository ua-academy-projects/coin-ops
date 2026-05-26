#!/usr/bin/env python3
import os
import subprocess
import json
import sys

def get_inventory():
    script_dir = os.path.dirname(os.path.realpath(__file__))
    terraform_dir = os.path.join(script_dir, "../../terraform")
    
    try:
        # Run terraform output from the terraform directory
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            check=True
        )
        tf_outputs = json.loads(result.stdout)
        
        inventory_data = tf_outputs.get("ansible_inventory_json", {}).get("value", {})
        internal_ips = tf_outputs.get("instance_internal_ips", {}).get("value", {})
        external_ips = tf_outputs.get("instance_external_ips", {}).get("value", {})
        
        # Identify bastion node if any
        bastion_ip = os.environ.get("BASTION_IP", "")
        bastion_private_ip = "127.0.0.1"
        if "bastion" in inventory_data and inventory_data["bastion"].get("hosts"):
            bastion_host = inventory_data["bastion"]["hosts"][0]
            bastion_ip = external_ips.get(bastion_host, "") or internal_ips.get(bastion_host, "")
            bastion_private_ip = internal_ips.get(bastion_host, "")

        cloud_provider = os.environ.get("CLOUD_PROVIDER", "aws")
        gcp_project_id = "coinops" if cloud_provider == "gcp" else os.environ.get("GCP_PROJECT_ID", "")

        hostvars = {}
        # Iterate over all hosts in all groups to build hostvars
        for group, data in inventory_data.items():
            for host in data.get("hosts", []):
                private_ip = internal_ips.get(host, "")
                public_ip = external_ips.get(host, "")
                
                # If there's a public IP, connect via public. Otherwise, private.
                ansible_host = public_ip if public_ip else private_ip
                
                # Determine SSH common args
                ssh_args = "-o StrictHostKeyChecking=no"
                if cloud_provider == "gcp" and not os.environ.get("PACKER_BUILD_NAME"):
                    ssh_args += f' -o ProxyCommand="gcloud compute start-iap-tunnel {host} %p --listen-on-stdin --project={gcp_project_id} --zone={{{{ zone | default(\'us-central1-a\') }}}}"'
                elif bastion_ip and host not in inventory_data.get("bastion", {}).get("hosts", []) and not os.environ.get("PACKER_BUILD_NAME"):
                    ssh_args += f" -o ProxyJump=ubuntu@{bastion_ip}"

                hostvars[host] = {
                    "ansible_host": ansible_host,
                    "private_ip": private_ip,
                    "public_ip": public_ip,
                    "ansible_user": "ubuntu",
                    "ansible_ssh_private_key_file": "~/.ssh/id_rsa",
                    "ansible_ssh_common_args": ssh_args
                }
        
        inventory_data["all"] = {
            "vars": {
                "tf_db_host": tf_outputs.get("db_instance_address", {}).get("value", ""),
                "tf_db_password": tf_outputs.get("db_password", {}).get("value", ""),
                "tf_database_url": tf_outputs.get("db_connection_string", {}).get("value", ""),
                "bastion_ip": bastion_ip,
                "bastion_private_ip": bastion_private_ip,
                "cloud_provider": cloud_provider,
                "gcp_project_id": gcp_project_id,
                "app_http_proxy": f"http://{bastion_private_ip}:3128" if bastion_private_ip != "127.0.0.1" else "",
                "app_no_proxy": "localhost,127.0.0.1,postgres,rabbitmq,redis,10.20.0.0/16"
            }
        }
        inventory_data["_meta"] = {"hostvars": hostvars}
        return inventory_data
    except Exception as e:
        print(f"Error reading terraform output: {e}", file=sys.stderr)
        return {}

if __name__ == "__main__":
    print(json.dumps(get_inventory(), indent=2))
