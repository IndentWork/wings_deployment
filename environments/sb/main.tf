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
    key = "sb.tfstate"
  }
}

provider "azurerm" {
  features {}
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
  vnet_address_space   = ["10.1.0.0/16"]
  postgres_subnet_cidr = "10.1.1.0/24"
  app_subnet_cidr      = "10.1.2.0/24"
}

module "key_vault" {
  source              = "../../modules/key-vault"
  project             = var.project
  env                 = var.env
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
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
