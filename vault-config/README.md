# Vault configuration

## Unseal Vault 
For more info, refer to [official documentation](https://www.vaultproject.io/docs/concepts/seal)

Reach Vault directly via `cloudflared access tcp` (see [../infra/README.md](../infra/README.md#reaching-vault-directly-for-vault-config-or-cli-use))
and unseal through that local proxy, or through the Vault UI at your `vault_endpoint`.
**Store your unseal and root keys very carefully and securely!**

You will need the root token for the initial Vault configuration below, and then you (and anyone else
granted access) can use Cloudflare Access GitHub login to get a scoped Vault token via JWT auth.

## Terraform Configuration
1. Replace _(two occurrences!)_ `YOUR_CREATED_TF_STATE_BUCKET_NAME` in [providers.tf](./providers.tf)
2. Change required values in [vault.auto.tfvars](./vault.auto.tfvars)
    ```
    cloudflare_teams_name = "your-cloudflare-for-teams-team-name"

    # emails to assing admin policy to
    vault_admins = [
        "you@example.com"
    ]
    ```
3. Optionally, adjust optional values in [vault.auto.tfvars](./vault.auto.tfvars)
4. Export the Vault root token _(alternatively you will be asked to pass it in by Terraform on each command)_
    ```bash
    export TF_VAR_VAULT_ROOT_TOKEN=
    ```
5. In a separate terminal, keep the local proxy to Vault's raw API running (see [../infra/README.md](../infra/README.md#reaching-vault-directly-for-vault-config-or-cli-use)) - this module's provider talks to `http://127.0.0.1:8200`.

## Terraform Deployment
1. Run `terraform init`
2. Run `terraform apply` and confirm changes
    - Terraform will output commands for getting fresh Vault token using Cloudflare Access JWT auth
3. You are done and your Zero-Trust Vault is configured!
