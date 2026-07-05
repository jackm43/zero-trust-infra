data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "vault_instance" {
  name = "vault-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "vault_instance" {
  name = "vault-instance"
  role = aws_iam_role.vault_instance.name
}

# Deny-all inbound; the instance is only reachable via the outbound-only
# Cloudflare Tunnel connection, mirroring the original GCE "no-ssh" tag intent.
resource "aws_security_group" "vault" {
  name        = "vault-no-inbound"
  description = "No inbound rules - Cloudflare Tunnel provides all connectivity"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# This is where we configure the server (aka instance).
# We need to template Cloudflare Tunnel ID only, as credentials are fetched
# from AWS Secrets Manager at boot.
resource "aws_instance" "vault" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.aws_instance_type
  iam_instance_profile   = aws_iam_instance_profile.vault_instance.name
  vpc_security_group_ids = [aws_security_group.vault.id]

  user_data = templatefile(
    "./templates/aws-instance-startup-script.sh",
    {
      aws_region           = var.aws_region
      cf_tunnel_id         = cloudflare_zero_trust_tunnel_cloudflared.vault.id
      tunnel_secret_name   = aws_secretsmanager_secret.cloudflare_tunnel_credentials.name
      vault_s3_bucket_name = aws_s3_bucket.vault_storage_backend.bucket
      vault_hostname       = "${var.vault_subdomain}.${var.cloudflare_zone_name}"
      vault_ssh_hostname   = "${var.vault_subdomain}${var.vault_subdomain_suffix_ssh}.${var.cloudflare_zone_name}"
      vault_ssh_users      = local.vault_ssh_users
      vault_ssh_ca_key     = cloudflare_zero_trust_access_short_lived_certificate.vault_ssh.public_key

      # if KMS auto-unseal is enabled
      vault_kms_auto_unseal = var.vault_kms_auto_unseal
      vault_kms_key_id      = var.vault_kms_auto_unseal ? aws_kms_key.vault_auto_unseal[0].key_id : ""
      aws_kms_region        = var.aws_region
    }
  )

  tags = {
    Name = "vault"
  }
}
