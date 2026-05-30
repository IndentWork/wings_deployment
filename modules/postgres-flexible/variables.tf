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

variable "delegated_subnet_id" {
  description = "ID of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers"
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the private DNS zone for Postgres"
  type        = string
}

variable "key_vault_id" {
  description = "ID of the Key Vault where the admin password secret will be stored"
  type        = string
}

variable "postgres_version" {
  description = "Postgres major version"
  type        = string
  default     = "14"
}

variable "sku_name" {
  description = "Postgres Flexible Server SKU"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB"
  type        = number
  default     = 32768
}

variable "administrator_login" {
  description = "Admin username for the Postgres server"
  type        = string
  default     = "wingsadmin"
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
