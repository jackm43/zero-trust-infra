# Personal Zero-Trust HashiCorp Vault

Secrets are hard, especially for local development. This is why I took two of my favorite products 
([Cloudflare For Teams](https://www.cloudflare.com/teams/) and [HashiCorp Vault](https://www.vaultproject.io/))
and used them together to come up with a Zero-Trust Vault deployment that is easy to use from any of my workstations.

The focus was to achieve fast deployment and easy maintenance. Terraform takes care of the full deployment, and the full stack is deployed with two `terraform apply` commands, everything is configured and ready to go within minutes. 

## TLDR Stack
- **Terraform** putting everything together ❤️
- **Cloudflare for Teams**
    - **Cloudflare Tunnel** _(exposing Vault, SSH to internet)_
    - **Cloudflare Access**
        - Vault UI _(GitHub org + email restricted Access application)_
        - SSH Web Terminal _(SSH access to EC2 instance)_
        - Admin API path _(service-token only, used by the `vault-config` Terraform module)_
        - JWT Auth backend _(Vault auth)_
- **AWS**
    - **EC2 Instance** _(with deny-all inbound security group)_
    - **S3 Bucket** _(Vault storage backend)_
    - **Secrets Manager** _(Cloudflare Tunnel credentials store)_
    - _(optional)_ **KMS** _(for Vault auto-unseal)_

No WARP client is required anywhere in this stack - the Vault UI and SSH terminal are reached through the
browser via Cloudflare Access, and the `vault-config` Terraform module reaches Vault's raw API through
`cloudflared access tcp` using an Access service token.

## Estimated Costs
### Cloudflare 
Free. _(for up to 50 users)_

### AWS
A `t3.micro` instance and a small S3 bucket are inexpensive, but not covered by a perpetual free tier the
way the original GCP `e2-micro` design was. Check current [EC2](https://aws.amazon.com/ec2/pricing/on-demand/)
and [S3](https://aws.amazon.com/s3/pricing/) pricing for your region.

## Deployment 

The deployment process consists of two steps. The first one (Infra) is to deploy the Zero-Trust stack and the second one is configuring the Vault itself.

### 1. Pre-requisities
In order to deploy this stack, make sure you have:
- Terraform version 1.9+
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured with credentials for the target account
- An S3 bucket for Terraform state (e.g. `tf-state-vault-<your-account-id>`), created ahead of time
- Cloudflare account with Cloudflare for Teams (Zero Trust) enabled, plus:
    - A scoped Cloudflare API token (Account: Cloudflare Tunnel, Access: Apps and Policies, Zone: DNS - edit permissions)
    - A GitHub identity provider already configured under Access > Authentication (this repo attaches
      policies to an *existing* IdP rather than creating one, since Terraform can't read back an OAuth
      client secret safely)

### 2. Infra
Please refer to [infra folder](./infra/)

### 3. Vault configuration
Please refer to [vault-config folder](./vault-config/)

## Couple of notes
- Cloudflare Access policies require both GitHub org membership *and* a specific allowed email
  (`include`: GitHub org rule, `require`: an Access group of allowed emails) - see [infra/cloudflare-access.tf](./infra/cloudflare-access.tf).
- OIDC auth flow or automatic WARP auth to get the JWT token would be better, this will be implemented if and once supported.
- Why? You may ask. The next step is to configure my local development to load ENV variables based on the project directory.
