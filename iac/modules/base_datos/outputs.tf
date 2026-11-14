output "cluster_arn" {
  value = aws_rds_cluster.this.arn
}

output "secreto_arn" {
  value = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "nombre_bd" {
  value = var.nombre_bd
}

output "esquema_listo" {
  value = terraform_data.esquema.id
}
