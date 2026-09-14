locals {
  app_location = "francecentral"
}

resource "azurerm_virtual_network" "prod" {
  name                = "vnet-totvs-prod"
  location            = local.app_location
  resource_group_name = data.azurerm_resource_group.prod.name
  address_space       = ["10.42.0.0/16"]

  tags = {
    project     = "totvs"
    environment = "prod"
  }
}

# A workload-profile Container Apps environment needs its own delegated /27.
resource "azurerm_subnet" "container_apps" {
  name                 = "snet-container-apps"
  resource_group_name  = data.azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.prod.name
  address_prefixes     = ["10.42.0.0/27"]

  delegation {
    name = "container-apps"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = data.azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.prod.name
  address_prefixes     = ["10.42.0.32/28"]

  delegation {
    name = "postgres"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "totvs.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.prod.name

  tags = {
    project     = "totvs"
    environment = "prod"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                 = "link-vnet-totvs-prod"
  private_dns_zone_id  = azurerm_private_dns_zone.postgres.id
  virtual_network_id   = azurerm_virtual_network.prod.id
  registration_enabled = false
}

# All application containers share this external environment and send console
# and platform logs to the bounded Log Analytics workspace.
resource "azurerm_container_app_environment" "prod" {
  name                           = "cae-totvs-prod"
  location                       = local.app_location
  resource_group_name            = data.azurerm_resource_group.prod.name
  infrastructure_subnet_id       = azurerm_subnet.container_apps.id
  internal_load_balancer_enabled = false
  zone_redundancy_enabled        = false
  logs_destination               = "log-analytics"
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.prod.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = {
    project     = "totvs"
    environment = "prod"
  }
}

output "container_apps_environment_id" {
  description = "Shared Container Apps environment for the front end and API."
  value       = azurerm_container_app_environment.prod.id
}
