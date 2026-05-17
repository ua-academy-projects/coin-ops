locals {
    cloud = "azure"
}

module "network" {
    source = "./network"
    network_name = lookup(var.config.network, "name", "coinops-network")
    subnetwork_name = lookup(var.config.network, "subnet_name", "coinops-subnet")
    network_cidr = lookup(var.config.network, "cidr", "10.10.0.0/16")
    subnetwork_cidr = lookup(var.config.network, "cidr", "10.10.0.0/16")
    location = lookup(var.config.region_map, "azure", "westeurope")
    resource_group = lookup(var.config.clouds.azure, "resource_group", "coinops-dev-rg")
}

module "firewall" {
    source = "./firewall"
    name = "${lookup(var.config, "name_prefix", "coinops")}-nsg" # network security group
    location       = lookup(var.config.region_map, "azure", "westeurope")
    resource_group = lookup(var.config.clouds.azure, "resource_group", "coinops-dev-rg")
    subnet_id      = module.network.subnet_id

    rules = [
        {
            name = "allow-ssh-bastion"
            priority = 100
            direction = "Inbound"
            access = "Allow"
            protocol = "Tcp"
            port = "22"
            source = lookup(var.config.firewall, "ssh_source_ranges", ["0.0.0.0/0"])[0]
        },
        {
            name      = "allow-http"
            priority  = 200
            direction = "Inbound"
            access    = "Allow"
            protocol  = "Tcp"
            port      = "80"
            source    = "0.0.0.0/0"
        },
        {
            name      = "allow-outbound"
            priority  = 300
            direction = "Outbound"
            access    = "Allow"
            protocol  = "*"
            port      = "*"
            source    = "*"
        }
    ]
}


module "vm" {
    source = "./vm"
    # if instances if empty - no vm to this cloud is created
    for_each = var.instances
    
    name           = each.key
    location       = lookup(var.config.region_map, "azure", "westeurope")
    resource_group = lookup(var.config.clouds.azure, "resource_group", "coinops-dev-rg")

    # get size 
    # get size map for that tier  ({aws: "t3.micro", gcp: "e2-micro", azure: "Standard_D2a_v4"} 
    # lookup(({aws: "t3.micro", gcp: "e2-micro", azure: "Standard_D2a_v4"}, "azure", "Standard_D2a_v4")
    vm_size = lookup(
        lookup(var.config.instance_type_map, lookup(each.value, "size", var.config.defaults.size), {}),
        local.cloud,
        "Standard_D2a_v4"
    )

    image = lookup(
        var.config.image_map[lookup(each.value, "image", var.config.defaults.image)],
        "azure",
        "Canonical:ubuntu-24_04-lts:server:latest"
    )
    
    subnet_id      = module.network.subnet_id
    private_ip     = lookup(each.value, "private_ip", null)
    public_ip      = lookup(each.value, "public", false)
    ssh_user       = lookup(var.config.ssh, "user", "ubuntu")
    ssh_public_key = var.ssh_public_key
}