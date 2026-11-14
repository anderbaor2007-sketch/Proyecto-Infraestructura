resource "aws_secretsmanager_secret" "pasarela" {
  name                    = "${var.nombre}/pasarela-pagos"
  recovery_window_in_days = var.dias_recuperacion
}

resource "aws_secretsmanager_secret_version" "pasarela" {
  secret_id = aws_secretsmanager_secret.pasarela.id

  secret_string = jsonencode({
    url_base = var.url_base_inicial
    api_key  = "reemplazar-con-la-credencial-real"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
