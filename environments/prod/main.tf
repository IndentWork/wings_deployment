terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    key = "prod.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      recover_soft_deleted_key_vaults = true
      purge_soft_delete_on_destroy    = false
    }
  }
}

module "resource_group" {
  source    = "../../modules/resource-group"
  component = "rg"
  project   = var.project
  env       = var.env
  location  = var.location
}

module "app_service_plan" {
  source              = "../../modules/app-service"
  project             = var.project
  env                 = var.env
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  sku_name            = "S1"
}

module "network" {
  source               = "../../modules/network"
  project              = var.project
  env                  = var.env
  location             = module.resource_group.location
  resource_group_name  = module.resource_group.name
  vnet_address_space   = ["10.3.0.0/16"]
  postgres_subnet_cidr = "10.3.1.0/24"
  app_subnet_cidr      = "10.3.2.0/24"
}

module "key_vault" {
  source                     = "../../modules/key-vault"
  project                    = var.project
  env                        = var.env
  location                   = module.resource_group.location
  resource_group_name        = module.resource_group.name
  soft_delete_retention_days = var.kv_soft_delete_retention_days
  purge_protection_enabled   = var.kv_purge_protection_enabled
}

module "postgres" {
  source              = "../../modules/postgres-flexible"
  project             = var.project
  env                 = var.env
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  delegated_subnet_id = module.network.postgres_subnet_id
  private_dns_zone_id = module.network.private_dns_zone_id
  key_vault_id        = module.key_vault.vault_id
}

data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group_name
}

module "web_app" {
  source                  = "../../modules/web-app"
  project                 = var.project
  env                     = var.env
  location                = module.resource_group.location
  resource_group_name     = module.resource_group.name
  app_service_plan_id     = module.app_service_plan.id
  app_subnet_id           = module.network.app_subnet_id
  key_vault_id            = module.key_vault.vault_id
  image_version           = var.image_version
  acr_login_server        = data.azurerm_container_registry.acr.login_server
  acr_id                  = data.azurerm_container_registry.acr.id
  postgres_fqdn           = module.postgres.fqdn
  postgres_admin_login    = module.postgres.administrator_login
  postgres_admin_password = module.postgres.administrator_password
}
