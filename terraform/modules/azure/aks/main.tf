# aks - azure kubernetes cluster
resource "azurerm_resource_group" "aks" {
    name = "${var.name_prefix}-aks-rg"
    location = var.location
}

resource "azurerm_kubernetes_cluster" "this" {
    name = "${var.name_prefix}-aks"
    location = azurerm_resource_group.aks.location
    resource_group_name = azurerm_resource_group.aks.name
    # dns_prefix generates endpoint (coinops-aks-abc123.eastdenmark) that later is used to connect AKS to k3s config (to use helm upgrade, kubectl (AKS only))
    dns_prefix = "${var.name_prefix}-aks"

    # create a vm for AKS
    default_node_pool {
        name = "default"
        node_count = 1
        vm_size = "Standard_B2s_v2"
    }
    
    # permission to manage azure resources
    identity {
        type = "SystemAssigned"
    }
}

resource "helm_release" "jenkins" {
    name = "jenkins"
    repository = "https://charts.jenkins.io"
    chart = "jenkins"
    namespace = "cicd"
    create_namespace = true

    depends_on = [azurerm_kubernetes_cluster.this]

}

resource "cloudflare_record" "jenkins" {
    zone_id = var.cloudflare_zone_id
    name = "jenkins"
    type = "CNAME"
    content = azurerm_kubernetes_cluster.this.fqdn
    ttl = 60    #  # dns cache time 60 seconds (user opens app.coin-ops.pp.ua => dns resolver asks cloudflare where to go it redirects to alb and saves that answer for 60 sec)
    proxied = false
}