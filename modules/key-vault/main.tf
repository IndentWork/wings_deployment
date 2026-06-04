data "azurerm_client_config" "current" {}

locals {
  tags = merge(
    {
      project    = var.project
      env        = var.env
      managed_by = "terraform"
      owner      = "indentwork"
    },
    var.tags
  )
}

resource "azurerm_key_vault" "this" {
  name                       = "kv-${var.org}-${var.project}-${var.env}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  # Access policies are managed as separate azurerm_key_vault_access_policy
  # resources (one below for the deployer SP; web-app declares its own).
  # The inline access_policy block was removed because the azurerm provider
  # treats it as the complete set — every apply would reconcile away policies
  # owned by other modules, silently breaking Key Vault references in App
  # Service. Matches the Microsoft canonical reference template.

  tags = local.tags
}

# Allow the Terraform service principal to manage secrets during provisioning
# (postgres-flexible writes the admin password here, web-app writes the
# Django SECRET_KEY).
resource "azurerm_key_vault_access_policy" "terraform_sp" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
  ]
}
