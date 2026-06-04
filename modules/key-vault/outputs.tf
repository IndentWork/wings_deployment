output "vault_id" {
  description = "Key Vault resource ID — passed to postgres-flexible module to store secrets"
  value       = azurerm_key_vault.this.id
}

output "vault_uri" {
  description = "Key Vault URI — used by App Service for Key Vault references (SecretUri= form)"
  value       = azurerm_key_vault.this.vault_uri
}

output "vault_name" {
  description = "Key Vault name — used by App Service for Key Vault references (VaultName=...;SecretName=... form)"
  value       = azurerm_key_vault.this.name
}
