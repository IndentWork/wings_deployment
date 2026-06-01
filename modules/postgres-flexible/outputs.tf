output "fqdn" {
  description = "Postgres server FQDN — used to build DATABASE_URL on the App Service"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "server_name" {
  description = "Postgres server name"
  value       = azurerm_postgresql_flexible_server.this.name
}

output "administrator_login" {
  description = "Admin username"
  value       = var.administrator_login
}

output "password_secret_name" {
  description = "Key Vault secret name holding the admin password"
  value       = azurerm_key_vault_secret.postgres_password.name
}

output "administrator_password" {
  description = "Admin password — passed to web-app to construct DATABASE_URL"
  value       = random_password.admin.result
  sensitive   = true
}
