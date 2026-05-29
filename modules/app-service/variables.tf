variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment (dev, qa, prod, sb)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into"
  type        = string
}

variable "sku_name" {
  description = "App Service Plan SKU. Must be S1 or higher to support deployment slots."
  type        = string
  default     = "S1"
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
