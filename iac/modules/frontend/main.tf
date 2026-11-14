data "aws_caller_identity" "actual" {}

locals {
  tipos = {
    html = "text/html; charset=utf-8"
    js   = "application/javascript; charset=utf-8"
    css  = "text/css; charset=utf-8"
    svg  = "image/svg+xml"
    json = "application/json"
    ico  = "image/x-icon"
    png  = "image/png"
  }
  con_dominio = var.certificado_arn != ""
}

resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.nombre}-frontend-${data.aws_caller_identity.actual.account_id}"
  force_destroy = var.destruir_con_contenido
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.nombre}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "sitio" {
  name        = "${var.nombre}-sitio"
  default_ttl = 300
  max_ttl     = 3600
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

data "aws_cloudfront_cache_policy" "sin_cache" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "api" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_wafv2_web_acl" "this" {
  provider = aws.us_east_1
  name     = "${var.nombre}-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "limite-por-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.limite_waf
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.nombre}-limite-por-ip"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "reglas-comunes"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          name = "SizeRestrictions_BODY"

          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.nombre}-reglas-comunes"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "entradas-maliciosas"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.nombre}-entradas-maliciosas"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.nombre}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_All"
  aliases             = local.con_dominio ? [var.alias] : []
  web_acl_id          = aws_wafv2_web_acl.this.arn

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    domain_name = var.dominio_api
    origin_id   = "api"
    origin_path = "/${var.etapa_api}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = aws_cloudfront_cache_policy.sitio.id
    compress               = true
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.rutas_api

    content {
      path_pattern             = ordered_cache_behavior.value
      target_origin_id         = "api"
      viewer_protocol_policy   = "https-only"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = data.aws_cloudfront_cache_policy.sin_cache.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.api.id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = local.con_dominio ? null : true
    acm_certificate_arn            = local.con_dominio ? var.certificado_arn : null
    ssl_support_method             = local.con_dominio ? "sni-only" : null
    minimum_protocol_version       = local.con_dominio ? "TLSv1.2_2021" : null
  }
}

data "aws_iam_policy_document" "frontend" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket     = aws_s3_bucket.frontend.id
  policy     = data.aws_iam_policy_document.frontend.json
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_s3_object" "sitio" {
  for_each     = fileset(var.contenido, "**")
  bucket       = aws_s3_bucket.frontend.id
  key          = each.value
  source       = "${var.contenido}/${each.value}"
  etag         = filemd5("${var.contenido}/${each.value}")
  content_type = lookup(local.tipos, regex("[^.]+$", each.value), "application/octet-stream")
}

resource "aws_s3_object" "configuracion" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "config.js"
  content      = "window.TERRAFLEET = ${jsonencode(var.configuracion)};\n"
  content_type = "application/javascript; charset=utf-8"
}
