resource "azurerm_resource_group" "rg" {
  name     = "big-k8s-project-rg"
  location = "Norway East"
}
# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-big-k8s"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet for AKS nodes
resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Azure Kubernetes Service (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-big-k8s"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "bigk8s"

  default_node_pool {
    name       = "systempool"
    node_count = 2
    vm_size    = "Standard_B2s"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }
  
  #Enable monitoring addon
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks_logs.id
  }

  
  # attach to the VNet
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr       = "10.2.0.0/16"
    dns_service_ip     = "10.2.0.10"
  
  }


    # Assign AKS permission to ACR
  depends_on = [azurerm_container_registry.acr]

    # Allow AKS to pull images from ACR
  role_based_access_control_enabled = true

}

# Give AKS cluster pull access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}


# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "aks_logs" {
  name                = "law-big-k8s"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "bigk8sacr${random_integer.rand.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"
  admin_enabled       = false
}
resource "azurerm_public_ip" "aks_ingress_ip" {
  name                = "aks-ingress-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
# Random suffix so name is unique globally
resource "random_integer" "rand" {
  min = 10000
  max = 99999
}




