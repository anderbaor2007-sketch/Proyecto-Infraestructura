output "colas" {
  value = {
    for clave, cola in aws_sqs_queue.this : clave => {
      url    = cola.url
      arn    = cola.arn
      nombre = cola.name
    }
  }
}

output "topico_alertas_arn" {
  value = aws_sns_topic.alertas.arn
}

output "remitente" {
  value = aws_ses_email_identity.remitente.email
}
