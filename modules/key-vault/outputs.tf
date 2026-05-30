output "vault_id" {
  description = "Key Vault resource ID — passed to postgres-flexible module to store secrets"
  value       = azurerm_key_vault.this.id
}

output "vault_uri" {
  description = "Key Vault URI — used by App Service for Key Vault references"
  value       = azurerm_key_vault.this.vault_uri
}
