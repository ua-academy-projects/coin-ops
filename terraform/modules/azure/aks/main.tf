# aks - azure kubernetes cluster
resource "azurerm_resource_group" "aks" {
  name     = "${var.name_prefix}-aks-rg"
  location = var.location
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.name_prefix}-aks"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  # dns_prefix generates endpoint (coinops-aks-abc123.eastdenmark) that later is used to connect AKS to k3s config (to use helm upgrade, kubectl (AKS only))
  dns_prefix = "${var.name_prefix}-aks"

  # create a vm for AKS
  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_B2s_v2"
  }

  # permission to manage azure resources
  identity {
    type = "SystemAssigned"
  }
}

resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  namespace        = "cicd"
  create_namespace = true

  values = [
    templatefile("${path.module}/jenkins-values.yaml.tftpl", {
      casc_config = templatefile("${path.module}/jenkins-casc.yaml.tftpl", {
        github_repo_url = var.github_repo_url
        git_branch      = var.git_branch
      })
    })
  ]

  depends_on = [azurerm_kubernetes_cluster.this]
}
