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

  production_hostname = "${local.app_name}.azurewebsites.net"
  staging_hostname    = "${local.app_name}-staging.azurewebsites.net"

  # Key Vault reference syntax — App Service resolves these at runtime using
  # the slot's managed identity. The raw secret value never appears in app settings.
  secret_key_ref    = "@Microsoft.KeyVault(SecretUri=${var.key_vault_uri}secrets/django-secret-key)"
  db_password_ref   = "@Microsoft.KeyVault(SecretUri=${var.key_vault_uri}secrets/postgres-admin-password)"
}

data "azurerm_client_config" "current" {}

# Generate a Django SECRET_KEY and store it in Key Vault.
# The app setting references it via KV reference — the raw value never
# appears in app settings.
resource "random_password" "secret_key" {
  length  = 50
  special = true
}

resource "azurerm_key_vault_secret" "secret_key" {
  name         = "django-secret-key"
  value        = random_password.secret_key.result
  key_vault_id = var.key_vault_id
}

# -----------------------------------------------------------------------------
# Production slot (the main web app)
# -----------------------------------------------------------------------------

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
    always_on                               = true
    container_registry_use_managed_identity = true
  }

  app_settings = {
    "WINGS_SETTINGS"                      = "azure"
    "WINGS_ENV"                           = var.env
    "WEBSITES_PORT"                       = "8000"
    "SECRET_KEY"                          = local.secret_key_ref
    "DB_HOST"                             = var.postgres_fqdn
    "DB_USER"                             = var.postgres_admin_login
    "DB_PASSWORD"                         = local.db_password_ref
    "DB_NAME"                             = var.postgres_database_name
    "ALLOWED_HOSTS"                       = local.production_hostname
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  # ALLOWED_HOSTS is bound to the slot's actual hostname — must not swap.
  sticky_settings {
    app_setting_names = ["ALLOWED_HOSTS"]
  }

  tags = local.tags

  # Image version is managed by the CI/CD pipeline (via az webapp config container set
  # and slot swap), not by Terraform. Without this, Terraform would fight the pipeline.
  lifecycle {
    ignore_changes = [
      site_config[0].application_stack,
    ]
  }
}

# -----------------------------------------------------------------------------
# Staging slot — deploys land here first, then swap to production.
# -----------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  virtual_network_subnet_id = var.app_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      docker_image_name   = "${var.image_name}:${var.image_version}"
      docker_registry_url = "https://${var.acr_login_server}"
    }
    always_on                               = true
    container_registry_use_managed_identity = true
  }

  app_settings = {
    "WINGS_SETTINGS"                      = "azure"
    "WINGS_ENV"                           = var.env
    "WEBSITES_PORT"                       = "8000"
    "SECRET_KEY"                          = local.secret_key_ref
    "DB_HOST"                             = var.postgres_fqdn
    "DB_USER"                             = var.postgres_admin_login
    "DB_PASSWORD"                         = local.db_password_ref
    "DB_NAME"                             = var.postgres_database_name
    "ALLOWED_HOSTS"                       = local.staging_hostname
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack,
    ]
  }
}

# -----------------------------------------------------------------------------
# Production slot identity grants
# -----------------------------------------------------------------------------

resource "azurerm_key_vault_access_policy" "web_app" {
  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app.this.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

# -----------------------------------------------------------------------------
# Staging slot identity grants (separate managed identity, separate grants)
# -----------------------------------------------------------------------------

resource "azurerm_key_vault_access_policy" "web_app_staging" {
  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app_slot.staging.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging.identity[0].principal_id
}
