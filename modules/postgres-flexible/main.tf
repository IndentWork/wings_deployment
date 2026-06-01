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

resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*-_=+?"
}

resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-admin-password"
  value        = random_password.admin.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                   = "psql-${var.org}-${var.project}-${var.env}"
  location               = var.location
  resource_group_name    = var.resource_group_name
  version                = var.postgres_version
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  administrator_login    = var.administrator_login
  administrator_password = random_password.admin.result

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false

  tags = local.tags
}
