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
  description = "Managed identity principal ID of the web app"
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}
