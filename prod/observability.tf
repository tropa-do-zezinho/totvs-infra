# Centralizes Container Apps system and console logs for troubleshooting.
# The low daily cap protects the student subscription from an accidental
# high-volume log stream; logs past the cap are not ingested until the next day.
resource "azurerm_log_analytics_workspace" "prod" {
  name                = "log-totvs-prod"
  location            = local.app_location
  resource_group_name = data.azurerm_resource_group.prod.name
  sku                 = "PerGB2018"

  retention_in_days = 30
  daily_quota_gb    = 0.1

  tags = {
    project     = "totvs"
    environment = "prod"
  }
}

output "log_analytics_workspace_name" {
  description = "Workspace containing Container Apps console and system logs."
  value       = azurerm_log_analytics_workspace.prod.name
}
