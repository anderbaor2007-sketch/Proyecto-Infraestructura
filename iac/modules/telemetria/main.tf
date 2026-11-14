data "aws_caller_identity" "actual" {}

data "aws_iot_endpoint" "datos" {
  endpoint_type = "iot:Data-ATS"
}

locals {
  cuenta         = data.aws_caller_identity.actual.account_id
  base_glue      = replace(var.nombre, "-", "_")
  topico_equipos = "terrafleet/equipos"
}

resource "aws_dynamodb_table" "telemetria" {
  name         = "${var.nombre}-telemetria"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "equipoId"
  range_key    = "timestamp"

  attribute {
    name = "equipoId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "empresaId"
    type = "S"
  }

  global_secondary_index {
    name            = "empresa-timestamp"
    hash_key        = "empresaId"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_kinesis_stream" "telemetria" {
  name             = "${var.nombre}-telemetria"
  retention_period = var.retencion_stream_horas
  shard_count      = 1

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

data "aws_iam_policy_document" "asumir_iot" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["iot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "regla_iot" {
  name               = "${var.nombre}-regla-iot"
  assume_role_policy = data.aws_iam_policy_document.asumir_iot.json
}

data "aws_iam_policy_document" "regla_iot" {
  statement {
    actions   = ["kinesis:PutRecord", "kinesis:PutRecords"]
    resources = [aws_kinesis_stream.telemetria.arn]
  }
}

resource "aws_iam_role_policy" "regla_iot" {
  name   = "publicar-en-kinesis"
  role   = aws_iam_role.regla_iot.id
  policy = data.aws_iam_policy_document.regla_iot.json
}

resource "aws_iot_topic_rule" "telemetria" {
  name        = "${local.base_glue}_telemetria"
  enabled     = true
  sql         = "SELECT * FROM '${local.topico_equipos}/+/telemetria' WHERE isUndefined(equipoId) = false AND topic(3) = equipoId"
  sql_version = "2016-03-23"

  kinesis {
    role_arn      = aws_iam_role.regla_iot.arn
    stream_name   = aws_kinesis_stream.telemetria.name
    partition_key = "$${equipoId}"
  }

  depends_on = [aws_iam_role_policy.regla_iot]
}

resource "aws_iot_policy" "dispositivo" {
  name = "${var.nombre}-dispositivo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:Connect"]
        Resource = ["arn:aws:iot:${var.region}:${local.cuenta}:client/$${iot:Connection.Thing.ThingName}"]
      },
      {
        Effect   = "Allow"
        Action   = ["iot:Publish"]
        Resource = ["arn:aws:iot:${var.region}:${local.cuenta}:topic/${local.topico_equipos}/$${iot:Connection.Thing.ThingName}/telemetria"]
      }
    ]
  })
}

resource "aws_iot_thing" "dispositivo" {
  for_each = var.dispositivos
  name     = each.key
}

resource "aws_iot_certificate" "dispositivo" {
  for_each = var.dispositivos
  active   = true
}

resource "aws_iot_thing_principal_attachment" "dispositivo" {
  for_each  = var.dispositivos
  thing     = aws_iot_thing.dispositivo[each.key].name
  principal = aws_iot_certificate.dispositivo[each.key].arn
}

resource "aws_iot_policy_attachment" "dispositivo" {
  for_each = var.dispositivos
  policy   = aws_iot_policy.dispositivo.name
  target   = aws_iot_certificate.dispositivo[each.key].arn
}

resource "aws_s3_bucket" "historico" {
  bucket        = "${var.nombre}-historico-${local.cuenta}"
  force_destroy = var.destruir_con_contenido
}

resource "aws_s3_bucket_public_access_block" "historico" {
  bucket                  = aws_s3_bucket.historico.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "historico" {
  bucket = aws_s3_bucket.historico.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_glue_catalog_database" "telemetria" {
  name = "${local.base_glue}_telemetria"
}

resource "aws_glue_catalog_table" "eventos" {
  name          = "eventos"
  database_name = aws_glue_catalog_database.telemetria.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"            = "parquet"
    "projection.enabled"        = "true"
    "projection.anio.type"      = "integer"
    "projection.anio.range"     = "2026,2040"
    "projection.mes.type"       = "integer"
    "projection.mes.range"      = "1,12"
    "projection.mes.digits"     = "2"
    "projection.dia.type"       = "integer"
    "projection.dia.range"      = "1,31"
    "projection.dia.digits"     = "2"
    "storage.location.template" = "s3://${aws_s3_bucket.historico.bucket}/telemetria/anio=$${anio}/mes=$${mes}/dia=$${dia}/"
  }

  partition_keys {
    name = "anio"
    type = "string"
  }

  partition_keys {
    name = "mes"
    type = "string"
  }

  partition_keys {
    name = "dia"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.historico.bucket}/telemetria/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "equipoid"
      type = "string"
    }

    columns {
      name = "empresaid"
      type = "string"
    }

    columns {
      name = "latitud"
      type = "double"
    }

    columns {
      name = "longitud"
      type = "double"
    }

    columns {
      name = "velocidad"
      type = "double"
    }

    columns {
      name = "motor"
      type = "string"
    }

    columns {
      name = "timestamp"
      type = "bigint"
    }
  }
}

data "aws_iam_policy_document" "asumir_firehose" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${var.nombre}-firehose"
  assume_role_policy = data.aws_iam_policy_document.asumir_firehose.json
}

data "aws_iam_policy_document" "firehose" {
  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [aws_s3_bucket.historico.arn, "${aws_s3_bucket.historico.arn}/*"]
  }

  statement {
    actions   = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"]
    resources = [aws_kinesis_stream.telemetria.arn]
  }

  statement {
    actions = ["glue:GetTable", "glue:GetTableVersion", "glue:GetTableVersions"]
    resources = [
      "arn:aws:glue:${var.region}:${local.cuenta}:catalog",
      aws_glue_catalog_database.telemetria.arn,
      aws_glue_catalog_table.eventos.arn,
    ]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "entrega-historico"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose.json
}

resource "aws_kinesis_firehose_delivery_stream" "historico" {
  name        = "${var.nombre}-historico"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.telemetria.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = aws_s3_bucket.historico.arn
    prefix              = "telemetria/anio=!{timestamp:yyyy}/mes=!{timestamp:MM}/dia=!{timestamp:dd}/"
    error_output_prefix = "errores/!{firehose:error-output-type}/!{timestamp:yyyy-MM-dd}/"
    buffering_size      = 64
    buffering_interval  = 300

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }

      schema_configuration {
        database_name = aws_glue_catalog_database.telemetria.name
        table_name    = aws_glue_catalog_table.eventos.name
        role_arn      = aws_iam_role.firehose.arn
        region        = var.region
      }
    }
  }

  depends_on = [aws_iam_role_policy.firehose]
}

resource "aws_athena_workgroup" "telemetria" {
  name          = var.nombre
  force_destroy = true

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.historico.bucket}/athena-resultados/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
