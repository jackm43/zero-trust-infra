# AWS variables
variable "aws_region" {
  description = "AWS region to deploy the Vault instance and supporting resources into."
  type        = string
}

variable "aws_instance_type" {
  description = "EC2 instance type for the Vault host."
  type        = string
}

# Cloudflare Variables
variable "cloudflare_account_id" {
  description = "The Cloudflare account ID (Zero Trust account) the tunnel/Access apps live in."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_name" {
  description = "The Cloudflare zone (domain) to use, e.g. jsmunro.me."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "The Cloudflare zone ID for cloudflare_zone_name."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Scoped Cloudflare API token (replaces legacy email + Global API Key auth)."
  sensitive   = true
  type        = string
}

# GitHub Identity Provider / Access variables
variable "github_organization_name" {
  description = "GitHub organization required for Access login via the GitHub identity provider."
  type        = string
}

variable "github_identity_provider_id" {
  description = "UUID of the existing Cloudflare Access GitHub identity provider to scope policies to."
  type        = string
}

variable "vault_access_email" {
  description = "Email required (in addition to the GitHub org membership) to be granted Access to Vault/SSH."
  type        = string
}

# Vault variables
variable "vault_subdomain" {
  description = "The Vault subdomain to use, -ssh will be also created."
  type        = string
}

variable "vault_subdomain_suffix_ssh" {
  description = "The Vault subdomain suffix to use for SSH web terminal"
  type        = string
}

variable "vault_subdomain_suffix_admin" {
  type = string
}

variable "vault_users" {
  description = "Emails allowed into the Vault UI Access application. Defaults to [var.vault_access_email]."
  type        = list(any)
  default     = []
}

variable "vault_ssh_users" {
  description = "Emails allowed into the SSH Access application (and created as sudoers on the instance). Defaults to [var.vault_access_email]."
  type        = list(any)
  default     = []
}

variable "vault_kms_auto_unseal" {
  description = "Whether to create an AWS KMS key and configure Vault's awskms auto-unseal seal."
  type        = bool
}

variable "vault_kms_key_alias" {
  description = "Alias for the AWS KMS auto-unseal key."
  type        = string
}

variable "vault_s3_bucket_name" {
  description = "Prefix for the S3 bucket used as the Vault storage backend (suffixed with the AWS account ID for global uniqueness)."
  type        = string
}
