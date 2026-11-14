locals {
  colas = toset(["reservas", "resultados", "notificaciones"])
}

resource "aws_sqs_queue" "this" {
  for_each                   = local.colas
  name                       = "${var.nombre}-${each.key}"
  visibility_timeout_seconds = var.visibilidad_segundos
  message_retention_seconds  = var.retencion_segundos
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
}

resource "aws_sns_topic" "alertas" {
  name = "${var.nombre}-alertas-flota"
}

data "aws_iam_policy_document" "notificaciones" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.this["notificaciones"].arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.alertas.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "notificaciones" {
  queue_url = aws_sqs_queue.this["notificaciones"].id
  policy    = data.aws_iam_policy_document.notificaciones.json
}

resource "aws_sns_topic_subscription" "alertas_a_notificaciones" {
  topic_arn            = aws_sns_topic.alertas.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this["notificaciones"].arn
  raw_message_delivery = true
  depends_on           = [aws_sqs_queue_policy.notificaciones]
}

resource "aws_ses_email_identity" "remitente" {
  email = var.remitente
}
