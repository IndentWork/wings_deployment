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

  # Key Vault reference syntax — App Service resolves these at runtime using
  # the web app's managed identity. The raw secret value never appears in
  # app settings. Uses VaultName=...;SecretName=... form (Microsoft's
  # canonical reference syntax — simpler than the SecretUri= form, no URI
  # construction needed).
  secret_key_ref  = "@Microsoft.KeyVault(VaultName=${var.key_vault_name};SecretName=django-secret-key)"
  db_password_ref = "@Microsoft.KeyVault(VaultName=${var.key_vault_name};SecretName=postgres-admin-password)"
}

data "azurerm_client_config" "current" {}

# Generate a Django SECRET_KEY and store it in Key Vault. The app setting
# references it via KV reference — the raw value never appears in app settings.
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
# Web app (production only)
#
# Staging slot + blue-green swap have been removed for now — see
# docs/pipeline-architecture.md. The canonical Microsoft reference template
# (Azure-Samples/azure-django-postgres-flexible-appservice) deploys to a
# single web app with no slot; we follow the same pattern until the baseline
# is stable, then re-introduce slot swap as a focused PR.
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
    "POSTGRES_HOST"                       = var.postgres_fqdn
    "POSTGRES_USERNAME"                   = var.postgres_admin_login
    "POSTGRES_PASSWORD"                   = local.db_password_ref
    "POSTGRES_DATABASE"                   = var.postgres_database_name
    "POSTGRES_PORT"                       = "5432"
    "POSTGRES_SSL"                        = "require"
    "ALLOWED_HOSTS"                       = local.production_hostname
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  tags = local.tags

  # Image version is managed by the CI/CD pipeline (via az webapp config
  # container set), not by Terraform. Without this, Terraform would fight
  # the pipeline on each apply.
  lifecycle {
    ignore_changes = [
      site_config[0].application_stack,
    ]
  }
}

# -----------------------------------------------------------------------------
# Web app identity grants
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
