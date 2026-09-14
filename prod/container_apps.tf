resource "azurerm_user_assigned_identity" "acr_pull" {
  name                = "id-totvs-acr-pull"
  location            = local.app_location
  resource_group_name = data.azurerm_resource_group.prod.name

  tags = {
    project     = "totvs"
    environment = "prod"
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                            = azurerm_container_registry.prod.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.acr_pull.principal_id
  skip_service_principal_aad_check = true
}

resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "random_password" "worker_api_token" {
  length  = 48
  special = false
}

# KEDA needs Manage to read Service Bus queue runtime metrics. The Worker uses
# the separate queue-scoped Listen credential from servicebus.tf.
resource "azurerm_servicebus_namespace_authorization_rule" "scale_monitor" {
  name         = "scale-monitor"
  namespace_id = azurerm_servicebus_namespace.prod.id
  listen       = true
  send         = true
  manage       = true
}

resource "azurerm_container_app_environment_storage" "worker" {
  name                         = "worker-checkpoints"
  container_app_environment_id = azurerm_container_app_environment.prod.id
  account_name                 = azurerm_storage_account.application.name
  share_name                   = azurerm_storage_share.worker_checkpoints.name
  access_key                   = azurerm_storage_account.application.primary_access_key
  access_mode                  = "ReadWrite"
}

# A public bootstrap image lets Terraform establish the app and its FQDN before
# the first application main merge publishes a private ACR image. The image
# field is then owned by each application's GitHub Actions workflow.
resource "azurerm_container_app" "api" {
  name                         = "ca-totvs-api"
  container_app_environment_id = azurerm_container_app_environment.prod.id
  resource_group_name          = data.azurerm_resource_group.prod.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.acr_pull.id]
  }

  registry {
    server   = azurerm_container_registry.prod.login_server
    identity = azurerm_user_assigned_identity.acr_pull.id
  }

  secret {
    name  = "postgres-password"
    value = random_password.postgres_admin.result
  }

  secret {
    name  = "jwt-secret"
    value = random_password.jwt_secret.result
  }

  secret {
    name  = "storage-connection"
    value = azurerm_storage_account.application.primary_connection_string
  }

  secret {
    name  = "servicebus-send"
    value = azurerm_servicebus_queue_authorization_rule.api_send.primary_connection_string
  }

  secret {
    name  = "worker-api-token"
    value = random_password.worker_api_token.result
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 8080

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    http_scale_rule {
      name                = "http"
      concurrent_requests = "10"
    }

    container {
      name   = "api"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "SPRING_DATASOURCE_URL"
        value = "jdbc:postgresql://${azurerm_postgresql_flexible_server.prod.fqdn}:5432/${azurerm_postgresql_flexible_server_database.app.name}?sslmode=require"
      }

      env {
        name  = "SPRING_DATASOURCE_USERNAME"
        value = azurerm_postgresql_flexible_server.prod.administrator_login
      }

      env {
        name        = "SPRING_DATASOURCE_PASSWORD"
        secret_name = "postgres-password"
      }

      env {
        name  = "SPRING_DOCKER_COMPOSE_ENABLED"
        value = "false"
      }

      env {
        name        = "JWT_SECRET"
        secret_name = "jwt-secret"
      }

      env {
        name        = "AZURE_STORAGE_CONNECTION_STRING"
        secret_name = "storage-connection"
      }

      env {
        name  = "AZURE_STORAGE_CONTAINER_NAME"
        value = azurerm_storage_container.meetings.name
      }

      env {
        name  = "AZURE_STORAGE_SAS_EXPIRY_HOURS"
        value = "24"
      }

      env {
        name        = "AZURE_SERVICE_BUS_CONNECTION_STRING"
        secret_name = "servicebus-send"
      }

      env {
        name  = "AZURE_SERVICE_BUS_QUEUE_NAME"
        value = azurerm_servicebus_queue.analysis.name
      }

      # The API team will validate this token in the Worker insights endpoint.
      env {
        name        = "INSIGHTS_API_TOKEN"
        secret_name = "worker-api-token"
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.acr_pull]

  tags = {
    project     = "totvs"
    environment = "prod"
    component   = "api"
  }
}

resource "azurerm_container_app" "front" {
  name                         = "ca-totvs-front"
  container_app_environment_id = azurerm_container_app_environment.prod.id
  resource_group_name          = data.azurerm_resource_group.prod.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.acr_pull.id]
  }

  registry {
    server   = azurerm_container_registry.prod.login_server
    identity = azurerm_user_assigned_identity.acr_pull.id
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 3000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    http_scale_rule {
      name                = "http"
      concurrent_requests = "10"
    }

    container {
      name   = "front"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "API_BASE_URL"
        value = "https://${azurerm_container_app.api.ingress[0].fqdn}"
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.acr_pull]

  tags = {
    project     = "totvs"
    environment = "prod"
    component   = "front"
  }
}

resource "azurerm_container_app" "worker" {
  name                         = "ca-totvs-worker"
  container_app_environment_id = azurerm_container_app_environment.prod.id
  resource_group_name          = data.azurerm_resource_group.prod.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.acr_pull.id]
  }

  registry {
    server   = azurerm_container_registry.prod.login_server
    identity = azurerm_user_assigned_identity.acr_pull.id
  }

  secret {
    name  = "servicebus-listen"
    value = azurerm_servicebus_queue_authorization_rule.worker_listen.primary_connection_string
  }

  secret {
    name  = "servicebus-scale"
    value = azurerm_servicebus_namespace_authorization_rule.scale_monitor.primary_connection_string
  }

  secret {
    name  = "worker-api-token"
    value = random_password.worker_api_token.result
  }

  template {
    min_replicas = 0
    max_replicas = 1

    custom_scale_rule {
      name             = "servicebus-queue"
      custom_rule_type = "azure-servicebus"
      metadata = {
        queueName    = azurerm_servicebus_queue.analysis.name
        messageCount = "1"
      }

      authentication {
        secret_name       = "servicebus-scale"
        trigger_parameter = "connection"
      }
    }

    volume {
      name          = "checkpoints"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.worker.name
      mount_options = "uid=10001,gid=10001,dir_mode=0770,file_mode=0660"
    }

    container {
      name   = "worker"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 1.0
      memory = "2Gi"

      env {
        name        = "AZURE_SERVICE_BUS_CONNECTION_STRING"
        secret_name = "servicebus-listen"
      }

      env {
        name  = "AZURE_SERVICE_BUS_QUEUE_NAME"
        value = azurerm_servicebus_queue.analysis.name
      }

      env {
        name  = "WORKER_ALLOWED_DOWNLOAD_HOSTS"
        value = "${azurerm_storage_account.application.name}.blob.core.windows.net"
      }

      env {
        name  = "WORKER_OUTPUT_DIR"
        value = "/app/data/processed/requests"
      }

      # The Groq key is set as a Container App secret outside Terraform.
      env {
        name        = "GROQ_API_KEY"
        secret_name = "groq-api-key"
      }

      env {
        name  = "LLM_MODEL"
        value = "openai/gpt-oss-120b"
      }

      env {
        name  = "MAX_LLM_CALLS"
        value = "1"
      }

      env {
        name  = "LLM_RPM"
        value = "2"
      }

      env {
        name  = "LLM_MAX_RETRIES"
        value = "4"
      }

      env {
        name  = "LLM_REASONING_EFFORT"
        value = "low"
      }

      env {
        name  = "LLM_MAX_OUTPUT_TOKENS"
        value = "1536"
      }

      env {
        name  = "RAG_TOP_K"
        value = "3"
      }

      env {
        name  = "WORKER_MAX_FILE_MB"
        value = "100"
      }

      env {
        name  = "WORKER_DOWNLOAD_TIMEOUT_SECONDS"
        value = "120"
      }

      env {
        name  = "WORKER_RECEIVE_WAIT_SECONDS"
        value = "20"
      }

      env {
        name  = "WORKER_MAX_LOCK_RENEWAL_SECONDS"
        value = "3600"
      }

      env {
        name  = "WORKER_MAX_DELIVERY_COUNT"
        value = "3"
      }

      env {
        name  = "INSIGHTS_API_TIMEOUT_SECONDS"
        value = "60"
      }

      env {
        name  = "INSIGHTS_API_MAX_RETRIES"
        value = "3"
      }

      env {
        name  = "INSIGHTS_API_RETRY_BASE_SECONDS"
        value = "2"
      }

      env {
        name  = "INSIGHTS_API_URL"
        value = "https://${azurerm_container_app.api.ingress[0].fqdn}/api/v1/worker/insights"
      }

      env {
        name        = "INSIGHTS_API_TOKEN"
        secret_name = "worker-api-token"
      }

      volume_mounts {
        name = "checkpoints"
        path = "/app/data/processed/requests"
      }
    }
  }

  lifecycle {
    ignore_changes = [secret, template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.acr_pull]

  tags = {
    project     = "totvs"
    environment = "prod"
    component   = "worker"
  }
}

output "api_url" {
  value = "https://${azurerm_container_app.api.ingress[0].fqdn}"
}

output "front_url" {
  value = "https://${azurerm_container_app.front.ingress[0].fqdn}"
}

