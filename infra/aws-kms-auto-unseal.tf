resource "aws_kms_key" "vault_auto_unseal" {
  count = var.vault_kms_auto_unseal ? 1 : 0

  description         = "Vault auto-unseal key"
  enable_key_rotation = true
}

resource "aws_kms_alias" "vault_auto_unseal" {
  count = var.vault_kms_auto_unseal ? 1 : 0

  name          = "alias/${var.vault_kms_key_alias}"
  target_key_id = aws_kms_key.vault_auto_unseal[0].key_id
}

# Allow the vault instance role to use the key for auto-unseal
resource "aws_iam_role_policy" "vault_kms_auto_unseal" {
  count = var.vault_kms_auto_unseal ? 1 : 0

  name = "vault-kms-auto-unseal"
  role = aws_iam_role.vault_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      Resource = aws_kms_key.vault_auto_unseal[0].arn
    }]
  })
}
