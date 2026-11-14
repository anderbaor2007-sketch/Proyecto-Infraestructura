output "tabla_arn" {
  value = aws_dynamodb_table.telemetria.arn
}

output "tabla_nombre" {
  value = aws_dynamodb_table.telemetria.name
}

output "stream_arn" {
  value = aws_kinesis_stream.telemetria.arn
}

output "stream_nombre" {
  value = aws_kinesis_stream.telemetria.name
}

output "bucket_historico" {
  value = aws_s3_bucket.historico.bucket
}

output "base_athena" {
  value = aws_glue_catalog_database.telemetria.name
}

output "grupo_athena" {
  value = aws_athena_workgroup.telemetria.name
}

output "endpoint_iot" {
  value = data.aws_iot_endpoint.datos.endpoint_address
}

output "certificados_dispositivos" {
  sensitive = true
  value = {
    for clave, certificado in aws_iot_certificate.dispositivo : clave => {
      certificado = certificado.certificate_pem
      clave       = certificado.private_key
    }
  }
}
