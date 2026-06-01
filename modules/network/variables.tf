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

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
}

variable "postgres_subnet_cidr" {
  description = "CIDR for the Postgres delegated subnet"
  type        = string
}

variable "app_subnet_cidr" {
  description = "CIDR for the App Service VNet integration subnet"
  type        = string
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
