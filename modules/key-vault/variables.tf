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

variable "soft_delete_retention_days" {
  description = "Number of days soft-deleted secrets are retained. Minimum 7, maximum 90."
  type        = number
  default     = 90
}

variable "purge_protection_enabled" {
  description = "Whether purge protection is enabled. Set to false for non-prod environments that are regularly destroyed."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
