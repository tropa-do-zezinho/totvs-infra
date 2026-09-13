resource "azurerm_servicebus_namespace" "prod" {
  name                          = "sb-totvs-${substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 12)}"
  location                      = "francecentral"
  resource_group_name           = data.azurerm_resource_group.prod.name
  sku                           = "Standard"
  minimum_tls_version           = "1.2"
  local_auth_enabled            = true
  public_network_access_enabled = true

  tags = {
    project     = "totvs"
    environment = "prod"
  }
}

resource "azurerm_servicebus_queue" "analysis" {
  name                                 = "reunioes-para-analise"
  namespace_id                         = azurerm_servicebus_namespace.prod.id
  lock_duration                        = "PT5M"
  default_message_ttl                  = "PT12H"
  dead_lettering_on_message_expiration = true
  requires_duplicate_detection         = true
  max_delivery_count                   = 3
}

resource "azurerm_servicebus_queue_authorization_rule" "api_send" {
  name     = "api-send"
  queue_id = azurerm_servicebus_queue.analysis.id
  send     = true
  listen   = false
  manage   = false
}

resource "azurerm_servicebus_queue_authorization_rule" "worker_listen" {
  name     = "worker-listen"
  queue_id = azurerm_servicebus_queue.analysis.id
  send     = false
  listen   = true
  manage   = false
}

output "servicebus_namespace_name" {
  description = "Service Bus namespace for upload processing."
  value       = azurerm_servicebus_namespace.prod.name
}

output "servicebus_queue_name" {
  description = "Use this same queue name in both API and Worker."
  value       = azurerm_servicebus_queue.analysis.name
}
