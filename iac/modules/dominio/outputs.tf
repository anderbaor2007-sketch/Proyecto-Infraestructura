output "certificado_arn" {
  value = local.activo ? aws_acm_certificate_validation.this[0].certificate_arn : ""
}
