output "url_sitio" {
  value = "https://${local.origen_web}"
}

output "distribucion_cloudfront" {
  value = module.frontend.distribucion_id
}

output "bucket_frontend" {
  value = module.frontend.bucket
}

output "cognito_pool_id" {
  value = module.autenticacion.pool_id
}

output "cognito_cliente_id" {
  value = module.autenticacion.cliente_id
}

output "aurora_cluster_arn" {
  value = module.base_datos.cluster_arn
}

output "aurora_secreto_arn" {
  value = module.base_datos.secreto_arn
}

output "endpoint_iot" {
  value = module.telemetria.endpoint_iot
}

output "tabla_telemetria" {
  value = module.telemetria.tabla_nombre
}

output "historico_athena" {
  value = {
    bucket = module.telemetria.bucket_historico
    base   = module.telemetria.base_athena
    grupo  = module.telemetria.grupo_athena
  }
}

output "certificados_dispositivos" {
  value     = module.telemetria.certificados_dispositivos
  sensitive = true
}
