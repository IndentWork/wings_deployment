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
