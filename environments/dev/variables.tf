variable "project" {
  description = "Project name"
  type        = string
  default     = "wings"
}

variable "env" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "southindia"
}

variable "kv_soft_delete_retention_days" {
  description = "Number of days soft-deleted Key Vault secrets are retained"
  type        = number
  default     = 7
}

variable "kv_purge_protection_enabled" {
  description = "Whether purge protection is enabled on the Key Vault"
  type        = bool
  default     = false
}

