resource "aws_secretsmanager_secret" "pasarela" {
  name                    = "${var.nombre}/pasarela-pagos"
  recovery_window_in_days = var.dias_recuperacion
}