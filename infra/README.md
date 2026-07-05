# Infrastructure provisioning

## Terraform Configuration
1. Replace `YOUR_CREATED_TF_STATE_BUCKET_NAME` in [providers.tf](./providers.tf) with the S3 bucket you created for state.
2. Change required values in [vault.auto.tfvars](./vault.auto.tfvars):
    ```
    cloudflare_account_id = "xxxyyy"
    cloudflare_zone_name  = "example.com"
    cloudflare_zone_id    = "..."

    github_organization_name    = "your-github-org"
    github_identity_provider_id = "..." # UUID of an existing Cloudflare Access GitHub identity provider
    vault_access_email         = "you@example.com"
    ```
3. Optionally, adjust optional values in [vault.auto.tfvars](./vault.auto.tfvars)
4. Put secrets into a `.env` referencing 1Password (or your secret manager of choice) and run everything through it, e.g.:
    ```bash
    # .env
    TF_VAR_cloudflare_api_token="op://Vault/Item/field"
    AWS_ACCESS_KEY_ID="op://Vault/Item/field"
    AWS_SECRET_ACCESS_KEY="op://Vault/Item/field"
    ```
    ```bash
    op run --env-file=.env -- terraform apply
    ```

## Terraform Deployment
1. Run `terraform init`
2. Run `terraform apply` and confirm changes
    - Terraform will output your endpoints at the end
3. Wait for the instance to boot and install Vault/cloudflared - endpoints should come up online in the following order:
    - SSH Web Terminal (`vault_endpoint_ssh`)
    - Vault UI (`vault_endpoint`)
4. You are done and your Zero-Trust Vault is up and running - no WARP client needed anywhere.
5. Continue to [configuring the Vault](../vault-config/) itself

## Reaching Vault directly (for `vault-config` or CLI use)
Vault's raw API (needed for the `vault-config` module) is reached through the tunnel via a
service-token-gated Access application, using `cloudflared access tcp` instead of the WARP client.
Note `access tcp` takes the service token as flags, not `CF_ACCESS_CLIENT_ID`/`_SECRET` env vars
(those are for the interactive `access login`/`curl` subcommands):

```bash
CLIENT_ID=$(terraform output -raw vault_admin_service_token_client_id)
CLIENT_SECRET=$(terraform output -raw vault_admin_service_token_client_secret)
cloudflared access tcp --hostname "$(terraform output -raw vault_endpoint_admin_hostname)" \
  --url 127.0.0.1:8200 --service-token-id "$CLIENT_ID" --service-token-secret "$CLIENT_SECRET" &
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init
```

For interactive/human use, just go to `vault_endpoint` (`https://vault.jsmunro.me`) in a browser and log
in with GitHub - that's simpler than the admin path above, which exists for non-interactive automation.

## Browser rendering (SSH) and browser isolation (admin)
- The SSH app (`vault_endpoint_ssh`) already gets a browser-rendered terminal for free - it's inherent
  to Access applications of `type = "ssh"`, no extra config needed. Just visit the URL in a browser and
  log in with GitHub to get an in-browser terminal, in addition to the `cloudflared access ssh`/plain
  `ssh` CLI flow.
- The admin app's policy sets `isolation_required = true`, so if it's ever opened in a browser it's
  rendered through Cloudflare's isolated remote browser rather than touching the origin directly. This
  only takes effect once **Clientless Web Isolation** is turned on for the account (Zero Trust dashboard
  > Settings > Network) - that's an account-wide Gateway toggle affecting all Gateway traffic, so it's
  left as a manual step for you rather than flipped automatically from here.
