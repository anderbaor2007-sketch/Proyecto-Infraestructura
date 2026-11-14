data "archive_file" "paquete" {
  type        = "zip"
  source_dir  = var.codigo
  output_path = "${path.root}/.build/${var.nombre}.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.nombre}"
  retention_in_days = var.retencion_logs
}

data "aws_iam_policy_document" "asumir" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.nombre}-rol"
  assume_role_policy = data.aws_iam_policy_document.asumir.json
}

data "aws_iam_policy_document" "permisos" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  dynamic "statement" {
    for_each = var.permisos

    content {
      actions   = statement.value.acciones
      resources = statement.value.recursos

      dynamic "condition" {
        for_each = statement.value.condiciones

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.valores
        }
      }
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "permisos"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permisos.json
}

resource "aws_lambda_function" "this" {
  function_name    = var.nombre
  role             = aws_iam_role.this.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = var.manejador
  filename         = data.archive_file.paquete.output_path
  source_code_hash = data.archive_file.paquete.output_base64sha256
  memory_size      = var.memoria
  timeout          = var.tiempo
  layers           = var.capas

  dynamic "environment" {
    for_each = length(var.variables) > 0 ? [var.variables] : []

    content {
      variables = environment.value
    }
  }

  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy.this]
}
