data "azurerm_client_config" "current" {}

resource "azurerm_container_registry" "prod" {
  # Registry names are global. The subscription suffix keeps this name stable.
  name                = "acrtotvs${substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 12)}"
  resource_group_name = data.azurerm_resource_group.prod.name
  location            = "francecentral"
  sku                 = "Standard"

  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true

  tags = {
    project     = "totvs"
    environment = "prod"
  }
}

output "registry_name" {
  description = "Name of the registry used by application image workflows."
  value       = azurerm_container_registry.prod.name
}

output "registry_login_server" {
  description = "Registry hostname; images still require Entra authorization."
  value       = azurerm_container_registry.prod.login_server
}
