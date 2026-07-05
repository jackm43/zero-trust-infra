# suffix by account ID, as S3 bucket names are globally unique
resource "aws_s3_bucket" "vault_storage_backend" {
  bucket = "${var.vault_s3_bucket_name}-${data.aws_caller_identity.current.account_id}"

  # error on attempt to delete
  # if you are unsure what deletion of this bucket means, changing it is NOT RECOMMENDED
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "vault_storage_backend" {
  bucket = aws_s3_bucket.vault_storage_backend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "vault_storage_backend" {
  bucket = aws_s3_bucket.vault_storage_backend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_storage_backend" {
  bucket = aws_s3_bucket.vault_storage_backend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role_policy" "vault_storage_backend" {
  name = "vault-s3-storage-backend"
  role = aws_iam_role.vault_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
      ]
      Resource = [
        aws_s3_bucket.vault_storage_backend.arn,
        "${aws_s3_bucket.vault_storage_backend.arn}/*",
      ]
    }]
  })
}
