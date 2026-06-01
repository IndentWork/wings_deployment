locals {
  app_name = "app-${var.org}-${var.project}-${var.env}"

  tags = merge(
    {
      project    = var.project
      env        = var.env
      managed_by = "terraform"
      owner      = "indentwork"
    },
    var.tags
  )

  database_url = "postgresql://${var.postgres_admin_login}:${var.postgres_admin_password}@${var.postgres_fqdn}:5432/${var.postgres_database_name}?sslmode=require"
}

data "azurerm_client_config" "current" {}

# Generate a Django SECRET_KEY and store it in Key Vault.
resource "random_password" "secret_key" {
  length  = 50
  special = true
}

resource "azurerm_key_vault_secret" "secret_key" {
  name         = "django-secret-key"
  value        = random_password.secret_key.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_linux_web_app" "this" {
  name                = local.app_name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = var.app_service_plan_id

  virtual_network_subnet_id = var.app_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      docker_image_name   = "${var.image_name}:${var.image_version}"
      docker_registry_url = "https://${var.acr_login_server}"
    }
    always_on = true
  }

  app_settings = {
    "WINGS_SETTINGS"                      = "azure"
    "WINGS_ENV"                           = var.env
    "WEBSITES_PORT"                       = "8000"
    "SECRET_KEY"                          = random_password.secret_key.result
    "DATABASE_URL"                        = local.database_url
    "ALLOWED_HOSTS"                       = "${local.app_name}.azurewebsites.net"
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  tags = local.tags
}

# Grant the web app's managed identity permission to read secrets from Key Vault.
resource "azurerm_key_vault_access_policy" "web_app" {
  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app.this.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

# Grant the web app's managed identity permission to pull images from ACR.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}
