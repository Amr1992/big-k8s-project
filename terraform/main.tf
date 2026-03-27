terraform {
  backend "local" {
    path = "./terraform.tfstate"
  }
}
# A. Resource group change
resource "azurerm_resource_group" "rg" {
  name     = "big-k8s-project-rg"
  location = var.location
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
    name           = "systempool"
    node_count     = 2
    vm_size        = "Standard_D2s_v3"  # Changed from "Standard_B2s"
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
    service_cidr      = "10.2.0.0/16"
    dns_service_ip    = "10.2.0.10"

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

# Random suffix so name is unique globally
resource "random_integer" "rand" {
  min = 10000
  max = 99999
}

data "azurerm_client_config" "current" {}

# C. Replaced Key Vault block
resource "azurerm_key_vault" "kv" {
  name                       = "bigk8skv${random_integer.rand.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  sku_name                   = "standard"
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete"
    ]
  }
}

# D. Key Vault secret change
resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = var.db_password
  key_vault_id = azurerm_key_vault.kv.id
}

# SQL Server
resource "azurerm_mssql_server" "sqlsrv" {
  name                         = "big2025sql${random_integer.rand.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.sql_admin_password
}

# SQL Database
resource "azurerm_mssql_database" "sql_db" {
  name           = "big2025db"
  server_id      = azurerm_mssql_server.sqlsrv.id
  sku_name       = "S0"
  zone_redundant = false
}

# Private Endpoint (connects SQL to VNet)
resource "azurerm_private_endpoint" "sql_pe" {
  name                = "big2025-sql-pe"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.aks_subnet.id

  private_service_connection {
    name                           = "sql-priv-conn"
    private_connection_resource_id = azurerm_mssql_server.sqlsrv.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }
}
#dummy push #
