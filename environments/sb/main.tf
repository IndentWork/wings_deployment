terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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
