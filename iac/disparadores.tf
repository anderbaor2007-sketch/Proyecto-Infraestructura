resource "aws_lambda_event_source_mapping" "cobrar_reserva" {
  event_source_arn        = local.colas["reservas"].arn
  function_name           = module.fn_cobrar_reserva.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 10
  }
}

resource "aws_lambda_event_source_mapping" "confirmar_reserva" {
  event_source_arn        = local.colas["resultados"].arn
  function_name           = module.fn_confirmar_reserva.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 10
  }
}

resource "aws_lambda_event_source_mapping" "enviar_correo" {
  event_source_arn        = local.colas["notificaciones"].arn
  function_name           = module.fn_enviar_correo.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 10
  }
}

resource "aws_lambda_event_source_mapping" "procesar_telemetria" {
  event_source_arn                   = module.telemetria.stream_arn
  function_name                      = module.fn_procesar_telemetria.arn
  starting_position                  = "TRIM_HORIZON"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 1
  parallelization_factor             = 1
  bisect_batch_on_function_error     = true
  maximum_retry_attempts             = -1
  maximum_record_age_in_seconds      = -1
  function_response_types            = ["ReportBatchItemFailures"]
}
