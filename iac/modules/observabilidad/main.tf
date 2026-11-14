data "aws_caller_identity" "actual" {}

resource "aws_sns_topic" "operaciones" {
  name = "${var.nombre}-operaciones"
}

resource "aws_sns_topic_subscription" "correo" {
  count     = var.correo_alarmas == "" ? 0 : 1
  topic_arn = aws_sns_topic.operaciones.arn
  protocol  = "email"
  endpoint  = var.correo_alarmas
}

resource "aws_cloudwatch_metric_alarm" "errores_lambda" {
  for_each            = var.funciones
  alarm_name          = "${var.nombre}-${each.key}-errores"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operaciones.arn]
}

resource "aws_cloudwatch_metric_alarm" "limitacion_lambda" {
  for_each            = var.funciones
  alarm_name          = "${var.nombre}-${each.key}-limitacion"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operaciones.arn]
}

resource "aws_cloudwatch_metric_alarm" "profundidad_cola" {
  for_each            = var.colas
  alarm_name          = "${var.nombre}-cola-${each.key}-profundidad"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = each.value }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.umbral_cola
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operaciones.arn]
}

resource "aws_cloudwatch_metric_alarm" "retraso_kinesis" {
  alarm_name          = "${var.nombre}-kinesis-retraso-consumidor"
  namespace           = "AWS/Kinesis"
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  dimensions          = { StreamName = var.stream_nombre }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.umbral_retraso_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operaciones.arn]
}

resource "aws_cloudwatch_metric_alarm" "latencia_api" {
  alarm_name          = "${var.nombre}-api-latencia-p95"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiName = var.api_nombre, Stage = var.etapa_api }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 3
  threshold           = 2000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operaciones.arn]
}

resource "aws_s3_bucket" "auditoria" {
  bucket        = "${var.nombre}-auditoria-${data.aws_caller_identity.actual.account_id}"
  force_destroy = var.destruir_con_contenido
}

resource "aws_s3_bucket_public_access_block" "auditoria" {
  bucket                  = aws_s3_bucket.auditoria.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "auditoria" {
  statement {
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.auditoria.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.auditoria.arn}/AWSLogs/${data.aws_caller_identity.actual.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "auditoria" {
  bucket     = aws_s3_bucket.auditoria.id
  policy     = data.aws_iam_policy_document.auditoria.json
  depends_on = [aws_s3_bucket_public_access_block.auditoria]
}

resource "aws_cloudtrail" "this" {
  name                          = "${var.nombre}-auditoria"
  s3_bucket_name                = aws_s3_bucket.auditoria.id
  include_global_service_events = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.auditoria]
  is_multi_region_trail = true
}
