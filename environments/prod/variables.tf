variable "project" {
  description = "Project name"
  type        = string
  default     = "wings"
}

variable "env" {
  description = "Environment"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "southindia"
}

variable "kv_soft_delete_retention_days" {
  description = "Number of days soft-deleted Key Vault secrets are retained"
  type        = number
  default     = 90
}

variable "kv_purge_protection_enabled" {
  description = "Whether purge protection is enabled on the Key Vault"
  type        = bool
  default     = true
}

variable "image_version" {
  description = "Wings Docker image version to deploy. Promoted manually via PR — never use 'latest', the deploy pipeline compares version strings to decide whether to swap."
  type        = string
  default     = "0.6.0"
}

variable "acr_name" {
  description = "Container registry name (created by wings/ bootstrap)"
  type        = string
  default     = "acriwwings01"
}

variable "acr_resource_group_name" {
  description = "Resource group containing the ACR (created by wings/ bootstrap)"
  type        = string
  default     = "rg-iw-wings-bootstrap"
}
