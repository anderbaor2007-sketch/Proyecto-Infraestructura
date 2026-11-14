locals {
  activo = var.dominio != ""
}

data "aws_route53_zone" "this" {
  count        = local.activo ? 1 : 0
  name         = var.zona
  private_zone = false
}

resource "aws_acm_certificate" "this" {
  count             = local.activo ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = var.dominio
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validacion" {
  for_each = local.activo ? {
    for opcion in aws_acm_certificate.this[0].domain_validation_options : opcion.domain_name => opcion
  } : {}

  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = local.activo ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for registro in aws_route53_record.validacion : registro.fqdn]
}

resource "aws_route53_record" "sitio" {
  count   = local.activo ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.dominio
  type    = "A"

  alias {
    name                   = var.cloudfront_dominio
    zone_id                = var.cloudfront_zona_id
    evaluate_target_health = false
  }
}

resource "aws_route53_health_check" "sitio" {
  count             = local.activo ? 1 : 0
  fqdn              = var.dominio
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "${var.dominio}-salud"
  }
}
