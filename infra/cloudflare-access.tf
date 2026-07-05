locals {
  vault_users     = length(var.vault_users) > 0 ? var.vault_users : [var.vault_access_email]
  vault_ssh_users = length(var.vault_ssh_users) > 0 ? var.vault_ssh_users : [var.vault_access_email]
}

# GitHub identity provider already exists in this Zero Trust account
# ("GitHub - jsmunro org", referenced via var.github_identity_provider_id) -
# reused here rather than re-created, since Terraform can never read back the
# OAuth client_secret to manage it safely, and creating a second GitHub IdP
# would just be a redundant duplicate. Org scoping happens per-policy below.

# Email allowlist groups (OR'd internally), so multiple vault_users/vault_ssh_users
# can be supported while still combining with the GitHub org requirement via AND.
resource "cloudflare_zero_trust_access_group" "vault_users" {
  account_id = var.cloudflare_account_id
  name       = "vault-ui-allowed-emails"

  include = [for email in local.vault_users : { email = { email = email } }]
}

resource "cloudflare_zero_trust_access_group" "vault_ssh_users" {
  account_id = var.cloudflare_account_id
  name       = "vault-ssh-allowed-emails"

  include = [for email in local.vault_ssh_users : { email = { email = email } }]
}

# Require GitHub org membership (jsmunro) AND membership of the email allowlist group.
# Forced through Cloudflare's isolated remote browser (RBI) - this is the actual
# HTTP-fronted, browser-facing app, unlike vault-admin's raw TCP admin path.
# Requires "Clientless Web Isolation" to be turned on for the account (Zero Trust
# dashboard > Settings > Network) - an account-wide Gateway toggle affecting all
# Gateway traffic, so left as a manual step rather than flipped here; until then
# this policy just behaves like the others without the RBI enforcement.
resource "cloudflare_zero_trust_access_policy" "vault" {
  account_id = var.cloudflare_account_id
  name       = "GitHub org ${var.github_organization_name} + email allowlist"
  decision   = "allow"

  include = [{
    github_organization = {
      name                 = var.github_organization_name
      identity_provider_id = var.github_identity_provider_id
    }
  }]

  require = [{
    group = { id = cloudflare_zero_trust_access_group.vault_users.id }
  }]

  isolation_required = true
}

# Access application to apply zero trust policy to Vault UI
resource "cloudflare_zero_trust_access_application" "vault" {
  zone_id          = var.cloudflare_zone_id
  name             = "${var.vault_subdomain}.${var.cloudflare_zone_name}"
  domain           = "${var.vault_subdomain}.${var.cloudflare_zone_name}"
  session_duration = "1h"
  type             = "self_hosted"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.vault.id
    precedence = 1
  }]
}

# Require GitHub org membership (jsmunro) AND membership of the SSH email allowlist group.
resource "cloudflare_zero_trust_access_policy" "vault_ssh" {
  account_id = var.cloudflare_account_id
  name       = "GitHub org ${var.github_organization_name} + email allowlist (SSH)"
  decision   = "allow"

  include = [{
    github_organization = {
      name                 = var.github_organization_name
      identity_provider_id = var.github_identity_provider_id
    }
  }]

  require = [{
    group = { id = cloudflare_zero_trust_access_group.vault_ssh_users.id }
  }]
}

# Access application for SSH. Native SSH client access only (no browser-rendered
# terminal) - reached via `cloudflared access ssh-gen` / ssh ProxyCommand against
# this app's hostname, authenticated with the short-lived cert below.
resource "cloudflare_zero_trust_access_application" "vault_ssh" {
  zone_id          = var.cloudflare_zone_id
  name             = "${var.vault_subdomain}${var.vault_subdomain_suffix_ssh}.${var.cloudflare_zone_name}"
  domain           = "${var.vault_subdomain}${var.vault_subdomain_suffix_ssh}.${var.cloudflare_zone_name}"
  session_duration = "1h"
  type             = "ssh"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.vault_ssh.id
    precedence = 1
  }]
}

# Short-lived SSH CA certificate (replaces the old cloudflare_access_ca_certificate)
resource "cloudflare_zero_trust_access_short_lived_certificate" "vault_ssh" {
  zone_id = var.cloudflare_zone_id
  app_id  = cloudflare_zero_trust_access_application.vault_ssh.id
}

# Service token for non-interactive (Terraform/CI) access to Vault's raw API
# through the tunnel, via `cloudflared access tcp`. This avoids requiring the
# WARP client just to reach Vault directly with the root token.
resource "cloudflare_zero_trust_access_service_token" "vault_admin" {
  account_id = var.cloudflare_account_id
  name       = "vault-config-terraform"
}

resource "cloudflare_zero_trust_access_policy" "vault_admin" {
  account_id = var.cloudflare_account_id
  name       = "vault-config-terraform service token only"
  decision   = "allow"

  include = [{
    service_token = { token_id = cloudflare_zero_trust_access_service_token.vault_admin.id }
  }]
}

# TEMPORARY - added to unblock a specific interactive CLI session while the
# service-token-only headless path is being debugged separately. Reuses the
# same GitHub-org + email allowlist group as everywhere else (no new
# authorization boundary). Remove once no longer needed - see
# docs/superpowers/plans/2026-07-05-vault-oidc-sso.md Task 2.
resource "cloudflare_zero_trust_access_policy" "vault_admin_interactive_temp" {
  account_id = var.cloudflare_account_id
  name       = "GitHub org ${var.github_organization_name} + email allowlist (admin, temp)"
  decision   = "allow"

  include = [{
    github_organization = {
      name                 = var.github_organization_name
      identity_provider_id = var.github_identity_provider_id
    }
  }]

  require = [{
    group = { id = cloudflare_zero_trust_access_group.vault_users.id }
  }]
}

# Access application guarding the private, TCP-only admin path used by the
# vault-config Terraform module (service token; temporarily also allows
# interactive GitHub login - see policy comment above)
resource "cloudflare_zero_trust_access_application" "vault_admin" {
  zone_id          = var.cloudflare_zone_id
  name             = "${var.vault_subdomain}${var.vault_subdomain_suffix_admin}.${var.cloudflare_zone_name}"
  domain           = "${var.vault_subdomain}${var.vault_subdomain_suffix_admin}.${var.cloudflare_zone_name}"
  session_duration = "24h"
  type             = "self_hosted"

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.vault_admin.id
      precedence = 1
    },
    {
      id         = cloudflare_zero_trust_access_policy.vault_admin_interactive_temp.id
      precedence = 2
    },
  ]
}

# Secondary, non-isolated policy reusing the same GitHub-org + email
# allowlist group as the main "vault" policy. Deliberately NOT isolated
# (unlike cloudflare_zero_trust_access_policy.vault) - this gates the OIDC
# IdP redirect hop itself, and forcing that through Cloudflare's remote
# browser isolation risks breaking the authorization-code redirect chain
# back to Vault.
resource "cloudflare_zero_trust_access_policy" "vault_oidc_idp" {
  account_id = var.cloudflare_account_id
  name       = "GitHub org ${var.github_organization_name} + email allowlist (OIDC IdP)"
  decision   = "allow"

  include = [{
    github_organization = {
      name                 = var.github_organization_name
      identity_provider_id = var.github_identity_provider_id
    }
  }]

  require = [{
    group = { id = cloudflare_zero_trust_access_group.vault_users.id }
  }]
}

# Cloudflare Access acting as an OIDC identity provider for Vault's native
# "Login with OIDC" button (Access for SaaS, available on the Zero Trust
# Enterprise plan this account is on). Lets Vault do a real SSO redirect
# instead of requiring a manually pasted JWT.
resource "cloudflare_zero_trust_access_application" "vault_oidc" {
  zone_id = var.cloudflare_zone_id
  name    = "${var.vault_subdomain}.${var.cloudflare_zone_name} (OIDC SSO)"
  type    = "saas"

  saas_app = {
    auth_type     = "oidc"
    redirect_uris = ["https://${var.vault_subdomain}.${var.cloudflare_zone_name}/ui/vault/auth/oidc/oidc/callback"]
    scopes        = ["openid", "email", "profile"]
    grant_types   = ["authorization_code"]
  }

  policies = [{
    id         = cloudflare_zero_trust_access_policy.vault_oidc_idp.id
    precedence = 1
  }]
}
