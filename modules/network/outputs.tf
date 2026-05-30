output "vnet_id" {
  description = "VNet resource ID"
  value       = azurerm_virtual_network.this.id
}

output "postgres_subnet_id" {
  description = "Postgres delegated subnet ID — passed to postgres-flexible module"
  value       = azurerm_subnet.postgres.id
}

output "app_subnet_id" {
  description = "App Service VNet integration subnet ID — passed to app-service module"
  value       = azurerm_subnet.app.id
}

output "private_dns_zone_id" {
  description = "Postgres private DNS zone ID — passed to postgres-flexible module"
  value       = azurerm_private_dns_zone.postgres.id
}
