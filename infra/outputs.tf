output "vault_endpoint" {
  value = "https://${cloudflare_dns_record.vault.name}"
}

output "vault_endpoint_ssh" {
  value = "https://${cloudflare_dns_record.vault_ssh.name}"
}

output "vault_endpoint_admin_hostname" {
  description = "Hostname to pass to `cloudflared access tcp --hostname <this> --url 127.0.0.1:8200` to reach Vault's raw API without WARP."
  value       = cloudflare_dns_record.vault_admin.name
}

output "access_vault_jwt_aud" {
  value = cloudflare_zero_trust_access_application.vault.aud
}

output "vault_admin_service_token_client_id" {
  value = cloudflare_zero_trust_access_service_token.vault_admin.client_id
}

output "vault_admin_service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.vault_admin.client_secret
  sensitive = true
}

output "vault_oidc_app_id" {
  description = "UUID of the Cloudflare Access SaaS Application acting as Vault's OIDC IdP - used to build the OIDC discovery URL in vault-config."
  value       = cloudflare_zero_trust_access_application.vault_oidc.id
}

output "vault_oidc_client_id" {
  value = cloudflare_zero_trust_access_application.vault_oidc.saas_app.client_id
}

output "vault_oidc_client_secret" {
  value     = cloudflare_zero_trust_access_application.vault_oidc.saas_app.client_secret
  sensitive = true
}
