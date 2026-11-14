data "aws_caller_identity" "actual" {}

resource "aws_s3_bucket" "fotos" {
  bucket        = "${var.nombre}-fotos-${data.aws_caller_identity.actual.account_id}"
  force_destroy = var.destruir_con_contenido
}

resource "aws_s3_bucket_public_access_block" "fotos" {
  bucket                  = aws_s3_bucket.fotos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fotos" {
  bucket = aws_s3_bucket.fotos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "fotos" {
  bucket = aws_s3_bucket.fotos.id

  cors_rule {
    allowed_methods = ["GET", "POST", "PUT"]
    allowed_origins = var.origenes_permitidos
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

data "aws_iam_policy_document" "fotos" {
  statement {
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.fotos.arn, "${aws_s3_bucket.fotos.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "fotos" {
  bucket     = aws_s3_bucket.fotos.id
  policy     = data.aws_iam_policy_document.fotos.json
  depends_on = [aws_s3_bucket_public_access_block.fotos]
}

resource "aws_s3_bucket_versioning" "fotos" {
  bucket = aws_s3_bucket.fotos.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "fotos" {
  bucket     = aws_s3_bucket.fotos.id
  depends_on = [aws_s3_bucket_versioning.fotos]

  rule {
    id     = "limpieza"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}