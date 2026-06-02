output "name" {
  description = "Web app name"
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default Azure-assigned hostname (e.g. app-iw-wings-dev.azurewebsites.net)"
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "Web app URL"
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "principal_id" {
  description = "Managed identity principal ID of the production slot"
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_hostname" {
  description = "Default hostname of the staging slot"
  value       = azurerm_linux_web_app_slot.staging.default_hostname
}

output "staging_url" {
  description = "Staging slot URL"
  value       = "https://${azurerm_linux_web_app_slot.staging.default_hostname}"
}
