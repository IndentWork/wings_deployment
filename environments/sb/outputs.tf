output "image_version" {
  description = "Wings image version intended for this environment — consumed by the deploy pipeline"
  value       = var.image_version
}

output "web_app_name" {
  description = "Web app name — used by the deploy pipeline for slot operations"
  value       = module.web_app.name
}

output "resource_group_name" {
  description = "Resource group name — used by the deploy pipeline"
  value       = module.resource_group.name
}
