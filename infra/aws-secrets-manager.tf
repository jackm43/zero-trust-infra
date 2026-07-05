resource "aws_secretsmanager_secret" "cloudflare_tunnel_credentials" {
  name = "cloudflare-tunnel-credentials"
}

resource "aws_secretsmanager_secret_version" "cloudflare_tunnel_credentials" {
  secret_id = aws_secretsmanager_secret.cloudflare_tunnel_credentials.id

  secret_string = jsonencode({
    AccountTag   = var.cloudflare_account_id
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.vault.id
    TunnelName   = cloudflare_zero_trust_tunnel_cloudflared.vault.name
    TunnelSecret = random_id.tunnel_secret.b64_std
  })
}

resource "aws_iam_role_policy" "vault_secrets_access" {
  name = "vault-secrets-access"
  role = aws_iam_role.vault_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_secretsmanager_secret.cloudflare_tunnel_credentials.arn
    }]
  })
}
