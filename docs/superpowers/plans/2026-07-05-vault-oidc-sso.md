# Vault OIDC SSO via Cloudflare Access for SaaS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Vault's manual-JWT-paste login with a real OIDC SSO redirect, using Cloudflare Access's "Access for SaaS" feature as the identity provider.

**Architecture:** `infra/` gains a new Cloudflare Access "SaaS Application" (type `saas`, `auth_type = "oidc"`) acting as Vault's OIDC IdP, gated by the same GitHub-org + email-allowlist group already used elsewhere. `vault-config/` swaps its existing `jwt`-type auth backend for an `oidc`-type one pointed at that new IdP, reading the IdP's client credentials via the existing cross-stack `terraform_remote_state` pattern.

**Tech Stack:** Terraform (`hashicorp/cloudflare` ~> 5, `hashicorp/vault` ~> 4), HashiCorp Vault 2.0.3, Cloudflare Zero Trust Enterprise.

## Global Constraints

- No CLI OIDC login support - browser UI only (`allowed_redirect_uris` contains exactly one URI, the Vault UI callback).
- Reuse the existing `cloudflare_zero_trust_access_group.vault_users` group as the authorization boundary - do not create a new email allowlist.
- Old `jwt`-type auth backend and its role must be fully removed (clean cutover, not dual auth methods).
- This repo has no automated test suite for Terraform config - "tests" in this plan are `terraform validate`, `terraform plan` diff review, and a manual browser verification at the end. Treat each `terraform plan` review as the equivalent of "run the test and check the expected output."
- Every `terraform` command in `infra/` and `vault-config/` must be run through `op run --env-file=../op.env -- <command>` (from within the stack directory) to inject AWS/Cloudflare credentials - never run `terraform` directly, it will fail auth.
- `vault-config`'s `terraform` commands additionally require `TF_VAR_VAULT_ROOT_TOKEN` (or a `-var` flag) set to a valid Vault root/privileged token, AND a local proxy to Vault's admin API reachable at `http://127.0.0.1:8200` (see Task 2 prerequisites).

---

### Task 1: Add the Cloudflare Access SaaS Application (OIDC IdP) for Vault

**Files:**
- Modify: `infra/cloudflare-access.tf` (append new resources at end of file)
- Modify: `infra/outputs.tf` (append new outputs at end of file)

**Interfaces:**
- Consumes: `var.cloudflare_account_id`, `var.cloudflare_zone_id`, `var.vault_subdomain`, `var.cloudflare_zone_name`, `cloudflare_zero_trust_access_group.vault_users.id` (all already defined/exist in `infra/`).
- Produces (new Terraform outputs, consumed by Task 2):
  - `vault_oidc_app_id` (string) - the Access Application's UUID, used to build the OIDC discovery URL.
  - `vault_oidc_client_id` (string)
  - `vault_oidc_client_secret` (string, sensitive)

- [ ] **Step 1: Append the new Access policy and SaaS Application resources**

Add to the end of `infra/cloudflare-access.tf`:

```hcl
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
    scopes        = ["email", "profile"]
    grant_types   = ["authorization_code"]
  }

  policies = [{
    id         = cloudflare_zero_trust_access_policy.vault_oidc_idp.id
    precedence = 1
  }]
}
```

- [ ] **Step 2: Append the new outputs**

Add to the end of `infra/outputs.tf`:

```hcl
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
```

- [ ] **Step 3: Validate and plan**

Run (from `infra/`):
```bash
op run --env-file=../op.env -- terraform validate
op run --env-file=../op.env -- terraform plan -out=/tmp/tfplan-oidc-infra
```
Expected: `terraform validate` prints `Success! The configuration is valid.` The plan shows exactly **2 resources to add** (`cloudflare_zero_trust_access_policy.vault_oidc_idp`, `cloudflare_zero_trust_access_application.vault_oidc`), **0 to change, 0 to destroy**. If it shows changes to any *existing* resource (e.g. `vault_users` group, the main `vault` app/policy), stop and re-check Step 1 - nothing existing should be touched.

- [ ] **Step 4: Apply**

Run (from `infra/`):
```bash
op run --env-file=../op.env -- terraform apply /tmp/tfplan-oidc-infra
```
Expected: `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.`

- [ ] **Step 5: Verify the new outputs resolve**

Run (from `infra/`):
```bash
op run --env-file=../op.env -- terraform output vault_oidc_app_id
op run --env-file=../op.env -- terraform output vault_oidc_client_id
op run --env-file=../op.env -- terraform output vault_oidc_client_secret
```
Expected: first two print plain string values (a UUID and a client ID); the third prints `<sensitive>` (confirming it's marked sensitive, not that it's broken - use `-raw` if you need to see the actual value for debugging).

- [ ] **Step 6: Commit**

```bash
cd /home/jackm/projects/zero-trust-infra
git add infra/cloudflare-access.tf infra/outputs.tf
git commit -m "$(cat <<'EOF'
feat: add Cloudflare Access SaaS Application as Vault's OIDC IdP

Enables Vault's native OIDC login button via Access for SaaS, gated by
the same GitHub-org + email allowlist used by the existing Vault app.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Swap Vault's auth backend from manual-JWT to OIDC

**Files:**
- Delete: `vault-config/auth-cloudflare-jwt.tf`
- Create: `vault-config/auth-cloudflare-oidc.tf`

**Interfaces:**
- Consumes: `data.terraform_remote_state.infra.outputs.vault_oidc_app_id`, `.vault_oidc_client_id`, `.vault_oidc_client_secret`, `.vault_endpoint` (all produced by Task 1 / already-existing infra outputs), `var.cloudflare_teams_name`, `var.vault_admins`, `var.vault_token_ttl` (all already defined in `vault-config/variables.tf`).
- Produces: `vault_jwt_auth_backend.access_oidc` (accessor consumed by the identity alias in this same file).

**Prerequisite - reaching Vault:** `vault-config`'s `vault` provider talks to `http://127.0.0.1:8200`, which must be a live proxy to Vault's admin API. In a separate terminal, run (and leave running):
```bash
cd /home/jackm/projects/zero-trust-infra/infra
CLIENT_ID=$(op run --env-file=../op.env -- terraform output -raw vault_admin_service_token_client_id)
CLIENT_SECRET=$(op run --env-file=../op.env -- terraform output -raw vault_admin_service_token_client_secret)
cloudflared access tcp --hostname vault-admin.jsmunro.me --url 127.0.0.1:8200 \
  --service-token-id "$CLIENT_ID" --service-token-secret "$CLIENT_SECRET"
```
This path was intermittently unreliable during design (suspected WSL2/QUIC transport issue, not fully root-caused). If it hangs or bad-handshakes: kill it, clear `~/.cloudflared/vault-admin.jsmunro.me-*-token`, and retry. If it still fails, this task is blocked on that connectivity - do not attempt to work around it by re-adding the interactive Access policy from earlier in this project (that was reverted deliberately; re-adding it is a separate, explicit decision, not a default fallback).

You'll also need a valid Vault root/privileged token for `TF_VAR_VAULT_ROOT_TOKEN` - if the original initial root token was already revoked, generate a new one first via `vault operator generate-root` (using the KMS-recovery Shamir key stored in the 1Password item recorded during Vault's initial setup) or log into the Vault UI with an existing privileged credential and mint a new token via `vault token create -policy=vault-admin`.

- [ ] **Step 1: Remove the old JWT auth config**

```bash
cd /home/jackm/projects/zero-trust-infra/vault-config
git rm auth-cloudflare-jwt.tf
```

- [ ] **Step 2: Write the new OIDC auth config**

Create `vault-config/auth-cloudflare-oidc.tf`:

```hcl
resource "vault_jwt_auth_backend" "access_oidc" {
  description = "Cloudflare Access OIDC auth backend"
  type        = "oidc"
  path        = "oidc"

  oidc_discovery_url = "https://${var.cloudflare_teams_name}.cloudflareaccess.com/cdn-cgi/access/sso/oidc/${data.terraform_remote_state.infra.outputs.vault_oidc_app_id}"
  oidc_client_id     = data.terraform_remote_state.infra.outputs.vault_oidc_client_id
  oidc_client_secret = data.terraform_remote_state.infra.outputs.vault_oidc_client_secret

  default_role = "default"
}

resource "vault_jwt_auth_backend_role" "default" {
  backend   = vault_jwt_auth_backend.access_oidc.path
  role_type = "oidc"
  role_name = "default"

  allowed_redirect_uris = ["${data.terraform_remote_state.infra.outputs.vault_endpoint}/ui/vault/auth/oidc/oidc/callback"]
  user_claim            = "email"
  oidc_scopes           = ["email", "profile"]

  token_policies = ["default"]
  token_ttl      = var.vault_token_ttl
  token_max_ttl  = var.vault_token_ttl
}

resource "vault_identity_entity" "vault_admin" {
  name     = "vault-admin"
  policies = ["vault-admin"]
}

resource "vault_identity_entity_alias" "vault_admin" {
  for_each       = toset(var.vault_admins)
  name           = each.key
  mount_accessor = vault_jwt_auth_backend.access_oidc.accessor
  canonical_id   = vault_identity_entity.vault_admin.id
}
```

Note: this duplicates the `vault_identity_entity`/`vault_identity_entity_alias` resources from the deleted file with the same names (`vault_admin`) - since the old file is being removed in the same change, there's no collision. Terraform will show this as an in-place update of the alias's `mount_accessor` (not a destroy/recreate of the entity itself), because the resource addresses (`vault_identity_entity.vault_admin`, `vault_identity_entity_alias.vault_admin`) are unchanged.

- [ ] **Step 3: Validate and plan**

Run (from `vault-config/`, with the tunnel from the prerequisite running in another terminal):
```bash
export TF_VAR_VAULT_ROOT_TOKEN='<your root/privileged token>'
op run --env-file=../op.env -- terraform validate
op run --env-file=../op.env -- terraform plan -out=/tmp/tfplan-oidc-vault
```
Expected: `terraform validate` succeeds. Plan shows: `vault_jwt_auth_backend.access_jwt` and `vault_jwt_auth_backend_role.default` **destroyed** (old ones, different resource address `access_jwt` vs new `access_oidc`), `vault_jwt_auth_backend.access_oidc` and `vault_jwt_auth_backend_role.default` (new resource, same role address reused) **created**, and `vault_identity_entity_alias.vault_admin` **updated in-place** (only `mount_accessor` changes). `vault_identity_entity.vault_admin` and `vault_policy.folder` (from `policies.tf`) should show **no changes**.

If the plan shows `vault_identity_entity.vault_admin` being destroyed/recreated, stop - that would orphan the `vault-admin` policy mapping. Check that the resource address literally matches `vault_identity_entity.vault_admin` (same as the deleted file) before proceeding.

- [ ] **Step 4: Apply**

```bash
op run --env-file=../op.env -- terraform apply /tmp/tfplan-oidc-vault
```
Expected: apply completes with the resource counts matching the plan from Step 3 (2 destroyed, 2 created, 1 changed, rest unchanged).

- [ ] **Step 5: Commit**

```bash
cd /home/jackm/projects/zero-trust-infra
git add vault-config/auth-cloudflare-jwt.tf vault-config/auth-cloudflare-oidc.tf
git commit -m "$(cat <<'EOF'
feat: swap Vault's manual-JWT auth for OIDC SSO

Vault's login now uses a real OIDC redirect through the Cloudflare
Access SaaS Application added in the previous commit, instead of
requiring a manually pasted JWT.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Manual verification of the login flow

**Files:** none (manual browser verification only)

**Interfaces:** none - this task consumes the deployed state from Tasks 1-2 and produces no artifacts, only a pass/fail confirmation.

- [ ] **Step 1: Confirm the old method is gone**

In a browser, go to `https://vault.jsmunro.me`. On Vault's login page, confirm the auth method dropdown no longer offers the old manual-JWT flow at path `jwt` (it should be entirely absent, replaced by an `oidc` method / "Login with OIDC" option).

- [ ] **Step 2: Log in via OIDC**

Select the OIDC method and click through. Expected: redirect to Cloudflare Access, resolves immediately (existing GitHub-org session, no new prompt), redirects back to Vault, and you land in the Vault UI dashboard already authenticated.

- [ ] **Step 3: Confirm the correct policy applied**

In the Vault UI (or via the CLI equivalent through the admin tunnel: `vault token lookup`), confirm the logged-in token has the `vault-admin` policy attached - this confirms `vault_identity_entity_alias.vault_admin`'s `email` claim mapping worked correctly end to end.

- [ ] **Step 4: Confirm root-token break-glass still works**

Separately, confirm you can still log in via the **Token** method using a valid Vault token (e.g. one minted via `vault token create -policy=vault-admin`) - this confirms the OIDC cutover didn't disturb Vault's built-in token auth (it can't be disabled, but worth confirming nothing else broke).

If Steps 2-3 fail, do not roll back by re-adding the old `jwt` backend - debug the OIDC config in place (likely culprits: `redirect_uris` mismatch between infra's SaaS app and vault-config's `allowed_redirect_uris`, or the discovery URL's app-ID segment). The root token from Vault's initial setup (or a freshly minted one, per Task 2's prerequisite note) remains available as break-glass access throughout.
