####
## REQUIRED
####
cloudflare_account_id = "314e7e015b5f4429c4e2da1e6ec93271"
cloudflare_zone_name  = "jsmunro.me"
cloudflare_zone_id    = "0317fdb8f32686c5173f4bcd7c5d1690"

github_organization_name    = "jsmunro"
github_identity_provider_id = "db8cf4be-fe22-4119-9346-6baf1a6d3f8a" # "GitHub - jsmunro org" identity provider
vault_access_email          = "jack@jsmunro.me"

####
## OPTIONAL (with defaults)
####
aws_region        = "ap-southeast-2"
aws_instance_type = "t3.micro"

# DNS records for Cloudflare Access Application and Cloudflare DNS
vault_subdomain              = "vault"
vault_subdomain_suffix_ssh   = "-ssh"
vault_subdomain_suffix_admin = "-admin"

vault_users = [
  # list of strings of emails to grant access to Vault UI, defaults to [var.vault_access_email]
]

vault_ssh_users = [
  # list of strings of emails to grant access to Vault instance SSH (sudoers), defaults to [var.vault_access_email]
]

vault_kms_auto_unseal = true
vault_kms_key_alias   = "vault-auto-unseal"
vault_s3_bucket_name  = "vault-storage-backend-au"
