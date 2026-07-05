# The random_id resource is used to generate a 35 character secret for the tunnel
resource "random_id" "tunnel_secret" {
  byte_length = 35
}

# A Named (locally-managed credentials) Tunnel resource
resource "cloudflare_zero_trust_tunnel_cloudflared" "vault" {
  account_id    = var.cloudflare_account_id
  name          = "zero-trust-personal-vault"
  tunnel_secret = random_id.tunnel_secret.b64_std
  config_src    = "cloudflare" # ingress rules managed remotely via the _config resource below
}

# Tunnel ingress configuration (replaces hand-rolled config.yml templating)
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "vault" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.vault.id

  config = {
    ingress = [
      {
        hostname = "*"
        path     = "^/_healthcheck$"
        service  = "http_status:200"
      },
      {
        hostname = "${var.vault_subdomain}.${var.cloudflare_zone_name}"
        service  = "http://localhost:8200"
      },
      {
        hostname = "${var.vault_subdomain}${var.vault_subdomain_suffix_ssh}.${var.cloudflare_zone_name}"
        service  = "ssh://localhost:22"
      },
      {
        # Raw Vault API for the vault-config Terraform module, reached via
        # `cloudflared access tcp` (Access service-token auth) - no WARP needed.
        hostname = "${var.vault_subdomain}${var.vault_subdomain_suffix_admin}.${var.cloudflare_zone_name}"
        service  = "tcp://localhost:8200"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

# Native tunnel private network route (replaces the old restapi provider hack)
resource "cloudflare_zero_trust_tunnel_cloudflared_route" "vault" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.vault.id
  network    = "${aws_instance.vault.private_ip}/32"
  comment    = "Vault EC2 instance private route"
}
