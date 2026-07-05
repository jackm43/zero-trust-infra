terraform {
  backend "s3" {
    bucket       = "tf-state-vault-115495764887"
    key          = "terraform/vault-config/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.9"
}

# this is data resource for fetching state from the infra Terraform folder
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "tf-state-vault-115495764887"
    key    = "terraform/infra/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "vault" {
  # Reaches Vault's raw API through `cloudflared access tcp --hostname
  # <vault_endpoint_admin_hostname> --url 127.0.0.1:8200`, run out-of-band
  # before `terraform apply` here (see ../infra output + README). This avoids
  # requiring the WARP client just to run this module.
  address = "http://127.0.0.1:8200"
  token   = var.VAULT_ROOT_TOKEN
}
