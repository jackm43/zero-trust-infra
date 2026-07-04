# Vault OIDC SSO via Cloudflare Access for SaaS

## Problem

Vault's login currently requires either the root token or a manually-pasted
JWT (`vault-config/auth-cloudflare-jwt.tf`, `role_type = "jwt"`). Both are
manual, copy-paste-driven flows. The account is on Cloudflare Zero Trust
Enterprise, which includes **Access for SaaS** (Access acting as an OIDC
identity provider for a downstream relying party). This lets Vault's own,
native "Login with OIDC" button perform a real SSO redirect instead.

## Goals

- Click "Login with OIDC" on Vault's UI → redirect to Cloudflare Access →
  resolves instantly (existing Access session, no new prompt) → redirect back
  to Vault → logged in with a real Vault token.
- No custom code (Worker/Durable Object) - standards-based OIDC only.
- Same authorization boundary as today: only GitHub org `jsmunro` members in
  the existing email allowlist (`vault_users` group) can complete the login.

## Non-goals

- CLI OIDC login (`vault login -method=oidc`) - browser UI only, per decision.
- mTLS / client-certificate requirement on Access policies - separate
  follow-up, not part of this change.
- Any Worker/Durable Object-based session bridging - considered and rejected
  (see "Alternatives considered").

## Design

### 1. `infra/` - new Cloudflare Access SaaS Application

Add a `cloudflare_zero_trust_access_application` resource with
`type = "saas"`, configured as an OIDC provider:

- `saas_app` block: `redirect_uris` limited to Vault's UI OIDC callback
  (`https://vault.jsmunro.me/ui/vault/auth/oidc/oidc/callback`), scopes
  `openid`, `email`, `profile`.
- Gated by the **same** `cloudflare_zero_trust_access_group.vault_users`
  group already used for the main `vault` Access application (reuse, not
  duplicate, so the outer Access gate and this inner IdP hop always agree on
  who's allowed).
- New outputs: `vault_oidc_client_id`, `vault_oidc_client_secret`
  (sensitive), `vault_oidc_issuer_url` (or discovery URL - exact attribute
  name confirmed against the `cloudflare_zero_trust_access_application`
  resource schema during implementation).

### 2. `vault-config/` - swap the auth backend

In `auth-cloudflare-jwt.tf` (renamed `auth-cloudflare-oidc.tf`):

- Remove `vault_jwt_auth_backend.access_jwt` (type `jwt`) and its role.
- Add `vault_jwt_auth_backend.access_oidc` with `type = "oidc"`, mounted at
  path `oidc`:
  - `oidc_discovery_url` = infra's new issuer/discovery output, read via the
    existing `data.terraform_remote_state.infra` pattern (same mechanism
    already used for `access_vault_jwt_aud`).
  - `oidc_client_id` / `oidc_client_secret` = infra's new outputs.
  - `default_role = "default"`.
- `vault_jwt_auth_backend_role.default`:
  - `role_type = "oidc"`.
  - `allowed_redirect_uris = ["https://vault.jsmunro.me/ui/vault/auth/oidc/oidc/callback"]`.
  - `user_claim = "email"`, `oidc_scopes = ["openid", "email", "profile"]`.
  - Keep existing `token_policies`, `token_ttl`, `token_max_ttl` from
    `var.vault_token_ttl`.
- `vault_identity_entity_alias.vault_admin`: repoint `mount_accessor` from
  the old jwt backend's accessor to the new oidc backend's accessor. No
  other change to the identity entity/policy mapping.

### 3. Rollout order

1. `terraform apply` in `infra/` first - purely additive (new Access
   Application), does not touch the existing `vault` app or current login
   path. Safe to apply anytime.
2. `terraform apply` in `vault-config/` second - this is the actual cutover
   (removes the old `jwt` backend, adds `oidc`). Do this while still holding
   a valid root-token session as a fallback, in case the OIDC redirect needs
   debugging before it's confirmed working.
3. Verify: load `vault.jsmunro.me`, click "Login with OIDC", confirm landing
   in Vault UI authenticated as `vault-admin` without any manual token entry.

### Known dependency / risk

`vault-config/providers.tf`'s `vault` provider reaches Vault's API through a
local proxy (`cloudflared access tcp` against `vault-admin.jsmunro.me`) that
has been unreliable during this session (intermittent bad-handshake/hang
behavior, root cause not fully resolved - suspected WSL2/QUIC transport
issue). Applying step 2 requires this path to work, or a temporary
workaround (e.g. running the apply from a non-WSL environment, or further
investigating the transport issue) before proceeding.

## Alternatives considered

- **Worker + Durable Object session bridge**: a Worker could inject a Vault
  token into the browser (e.g. by rewriting Vault UI's HTML to plant
  `localStorage` state) to achieve true zero-click login, with a Durable
  Object holding per-user session/token state. Rejected: relies on Vault
  UI's undocumented internal `localStorage` schema (fragile across Vault
  version upgrades), and introduces a second place capable of minting valid
  Vault sessions (increased attack surface, custom code to
  security-review/maintain) - for a marginal gain of removing a single
  button click on a personal, low-traffic Vault instance.
- **mTLS via a custom session-binding scheme**: considered for cookie-theft
  protection; Cloudflare Access already supports mTLS/client-certificate
  policy requirements natively, which is the standards-based equivalent -
  tracked as a separate follow-up, not built here.

## Testing / verification

- `terraform plan` reviewed for both stacks before apply (no unexpected
  destroys beyond the intended `jwt` backend removal).
- Manual verification of the full login redirect flow in-browser post-apply.
- Confirm the old manual-JWT-paste method no longer works (backend removed)
  and root-token login still works as break-glass.
