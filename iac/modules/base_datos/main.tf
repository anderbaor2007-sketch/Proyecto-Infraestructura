resource "aws_db_subnet_group" "this" {
  name       = "${var.nombre}-aurora"
  subnet_ids = var.subredes_ids
}

resource "aws_rds_cluster" "this" {
  cluster_identifier                  = "${var.nombre}-aurora"
  engine                              = "aurora-postgresql"
  engine_mode                         = "provisioned"
  engine_version                      = var.version_motor
  database_name                       = var.nombre_bd
  master_username                     = "terrafleet_admin"
  manage_master_user_password         = true
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [var.grupo_seguridad_id]
  enable_http_endpoint                = true
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  copy_tags_to_snapshot               = true
  backup_retention_period             = var.retencion_respaldo_dias
  preferred_backup_window             = "07:00-08:00"
  deletion_protection                 = var.proteger_borrado
  skip_final_snapshot                 = !var.proteger_borrado
  final_snapshot_identifier           = var.proteger_borrado ? "${var.nombre}-aurora-final" : null

  serverlessv2_scaling_configuration {
    min_capacity = var.capacidad_min
    max_capacity = var.capacidad_max
  }

  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster_instance" "this" {
  count              = 2
  identifier         = "${var.nombre}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  availability_zone  = var.zonas[count.index]
  promotion_tier     = count.index

  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "terraform_data" "esquema" {
  triggers_replace = [
    aws_rds_cluster.this.id,
    sha1(join("", [for archivo in sort(tolist(fileset(var.ruta_esquema, "*.sql"))) : filesha1("${var.ruta_esquema}/${archivo}")])),
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      CLUSTER_ARN = aws_rds_cluster.this.arn
      SECRET_ARN  = aws_rds_cluster.this.master_user_secret[0].secret_arn
      BASE        = var.nombre_bd
      REGION      = var.region
      RUTA        = var.ruta_esquema
    }

    command = <<-EOT
      set -euo pipefail
      for archivo in "$RUTA"/*.sql; do
        for intento in 1 2 3 4 5 6 7 8; do
          if aws rds-data execute-statement --region "$REGION" --resource-arn "$CLUSTER_ARN" --secret-arn "$SECRET_ARN" --database "$BASE" --sql "file://$archivo" > /dev/null; then
            break
          fi
          if [ "$intento" -eq 8 ]; then
            exit 1
          fi
          sleep 15
        done
      done
    EOT
  }

  depends_on = [aws_rds_cluster_instance.this]
}
