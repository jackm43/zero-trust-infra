# NOTE: modernized without live Terraform Registry access during initial drafting.
# Run `terraform init` / `terraform validate` and cross-check exact resource &
# argument names against the registry docs for cloudflare/cloudflare ~> 5.0 and
# hashicorp/aws ~> 5.0 before applying (this will be verified as part of this pass).

terraform {
  backend "s3" {
    bucket       = "tf-state-vault-115495764887"
    key          = "terraform/infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # native S3 state locking (Terraform >= 1.11, no DynamoDB table needed)
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  required_version = ">= 1.9"
}

# Providers
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "aws" {
  region = var.aws_region
}

provider "random" {}

data "aws_caller_identity" "current" {}
