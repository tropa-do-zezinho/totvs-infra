resource "azurerm_storage_account" "application" {
  name                            = "sttotvsapp${substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 12)}"
  resource_group_name             = data.azurerm_resource_group.prod.name
  location                        = "francecentral"
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  public_network_access_enabled   = true

  tags = {
    project     = "totvs"
    environment = "prod"
    purpose     = "application-uploads"
  }
}

resource "azurerm_storage_container" "meetings" {
  name                  = "reunioes"
  storage_account_id    = azurerm_storage_account.application.id
  container_access_type = "private"
}

output "application_storage_account_name" {
  description = "Storage account for application uploads; separate from Terraform state."
  value       = azurerm_storage_account.application.name
}

output "meetings_container_name" {
  description = "Private upload container."
  value       = azurerm_storage_container.meetings.name
}
