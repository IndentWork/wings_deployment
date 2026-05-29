variable "component" {
  description = "Component identifier (e.g. rg, app, psql)"
  type        = string
}

variable "project" {
  description = "Project name (e.g. wings)"
  type        = string
}

variable "env" {
  description = "Environment (dev, qa, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod", "sb"], var.env)
    error_message = "env must be one of: dev, qa, prod, sb"
  }
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Additional tags to merge into the resource group"
  type        = map(string)
  default     = {}
}
