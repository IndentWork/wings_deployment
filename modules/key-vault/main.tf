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
  name                = "kv-${var.project}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  # allow the Terraform service principal to manage secrets during provisioning
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge",
    ]
  }

  tags = local.tags
}
