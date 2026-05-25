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
        
        hostvars = {}
        # Iterate over all hosts in all groups to build hostvars
        for group, data in inventory_data.items():
            for host in data.get("hosts", []):
                private_ip = internal_ips.get(host, "")
                public_ip = external_ips.get(host, "")
                
                # If there's a public IP, connect via public. Otherwise, private.
                ansible_host = public_ip if public_ip else private_ip
                
                hostvars[host] = {
                    "ansible_host": ansible_host,
                    "private_ip": private_ip,
                    "public_ip": public_ip
                }
        
        inventory_data["all"] = {
            "vars": {
                "tf_db_host": tf_outputs.get("db_instance_address", {}).get("value", ""),
                "tf_db_password": tf_outputs.get("db_password", {}).get("value", ""),
                "tf_database_url": tf_outputs.get("db_connection_string", {}).get("value", "")
            }
        }
        inventory_data["_meta"] = {"hostvars": hostvars}
        return inventory_data
    except Exception as e:
        print(f"Error reading terraform output: {e}", file=sys.stderr)
        return {}

if __name__ == "__main__":
    print(json.dumps(get_inventory(), indent=2))
