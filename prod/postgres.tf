resource "random_password" "postgres_admin" {
  length      = 32
  special     = false
  min_upper   = 4
  min_lower   = 4
  min_numeric = 4
}

resource "azurerm_postgresql_flexible_server" "prod" {
  name                          = "pgtotvs${substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 12)}"
  resource_group_name           = data.azurerm_resource_group.prod.name
  location                      = local.app_location
  zone                          = "1"
  version                       = "16"
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  storage_tier                  = "P4"
  auto_grow_enabled             = false
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  administrator_login           = "totvsadmin"
  administrator_password        = random_password.postgres_admin.result
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  tags = {
    project     = "totvs"
    environment = "prod"
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = "totvs"
  server_id = azurerm_postgresql_flexible_server.prod.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

output "postgres_fqdn" {
  description = "Private DNS name of the PostgreSQL server."
  value       = azurerm_postgresql_flexible_server.prod.fqdn
}

output "postgres_database_name" {
  description = "Application database name."
  value       = azurerm_postgresql_flexible_server_database.app.name
}
