terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    key = "qa.tfstate"
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
