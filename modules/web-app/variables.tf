variable "org" {
  description = "Organization slug used in resource naming"
  type        = string
  default     = "iw"
}

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

variable "app_service_plan_id" {
  description = "ID of the App Service Plan this web app runs on"
  type        = string
}

variable "app_subnet_id" {
  description = "ID of the subnet used for App Service VNet integration"
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault resource ID — used to store the Django SECRET_KEY"
  type        = string
}

variable "key_vault_name" {
  description = "Key Vault name (e.g. kv-iw-wings-dev) — used to build Key Vault reference strings for app settings via the VaultName=...;SecretName=... syntax"
  type        = string
}

variable "image_name" {
  description = "Container image name in ACR (e.g. wings)"
  type        = string
  default     = "wings"
}

variable "image_version" {
  description = "Container image version tag (e.g. 0.4.0)"
  type        = string
}

variable "acr_login_server" {
  description = "ACR login server (e.g. acriwwings01.azurecr.io)"
  type        = string
}

variable "acr_id" {
  description = "Full ACR resource ID — used to assign AcrPull role to the web app's managed identity"
  type        = string
}

variable "postgres_fqdn" {
  description = "Postgres server FQDN"
  type        = string
}

variable "postgres_admin_login" {
  description = "Postgres admin username"
  type        = string
}

variable "postgres_database_name" {
  description = "Name of the Postgres database to connect to"
  type        = string
  default     = "postgres"
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
