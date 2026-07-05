# Create DNS records after Access Application is created (forced by referencing Application domain)
resource "cloudflare_dns_record" "vault" {
  zone_id = var.cloudflare_zone_id
  name    = cloudflare_zero_trust_access_application.vault.domain
  content = "${cloudflare_zero_trust_tunnel_cloudflared.vault.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "vault_ssh" {
  zone_id = var.cloudflare_zone_id
  name    = cloudflare_zero_trust_access_application.vault_ssh.domain
  content = "${cloudflare_zero_trust_tunnel_cloudflared.vault.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "vault_admin" {
  zone_id = var.cloudflare_zone_id
  name    = cloudflare_zero_trust_access_application.vault_admin.domain
  content = "${cloudflare_zero_trust_tunnel_cloudflared.vault.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}
