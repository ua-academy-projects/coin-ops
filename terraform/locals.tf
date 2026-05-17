locals {
  config         = yamldecode(trimspace(file("${path.root}/../config/config.yml")))
  cloud          = local.config.cloud
  ssh_public_key = trimspace(file(local.config.ssh.public_key_path))

  # HANDLING SET IN INSTANCES MANUALLY CLOUD PARAMETER
  # name - name of the vm, instance - all parameters ( size, image, cloud ... )
  # if cloud is not provided get general from local.config.cloud
  aws_instances = {
    for name, instance in local.config.instances :
    name => instance  # "bastion" => {size: "small", private_ip: "10.10.0.10", ...}
    if lookup(instance, "cloud", local.config.cloud) == "aws" # get cloud from instance only keep it if cloud is aws
  }
   gcp_instances = {
    for name, instance in local.config.instances :
    name => instance
    if lookup(instance, "cloud", local.config.cloud) == "gcp"
  }
  azure_instances = {
    for name, instance in local.config.instances :
    name => instance
    if lookup(instance, "cloud", local.config.cloud) == "azure"
  }
}

