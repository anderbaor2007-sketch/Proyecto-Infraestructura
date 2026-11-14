data "archive_file" "capa_comun" {
  type        = "zip"
  source_dir  = "${path.root}/../backend/capa_comun"
  output_path = "${path.root}/.build/capa-comun.zip"
}

resource "aws_lambda_layer_version" "comun" {
  layer_name               = "${local.nombre}-comun"
  filename                 = data.archive_file.capa_comun.output_path
  source_code_hash         = data.archive_file.capa_comun.output_base64sha256
  compatible_runtimes      = ["python3.12"]
  compatible_architectures = ["arm64"]
}

locals {
  codigo = "${path.root}/../backend/funciones"

  variables_bd = {
    DB_CLUSTER_ARN = module.base_datos.cluster_arn
    DB_SECRET_ARN  = module.base_datos.secreto_arn
    DB_NOMBRE      = module.base_datos.nombre_bd
  }

  permiso_bd = [
    { acciones = ["rds-data:ExecuteStatement"], recursos = [module.base_datos.cluster_arn] },
    { acciones = ["secretsmanager:GetSecretValue"], recursos = [module.base_datos.secreto_arn] },
  ]

  colas = module.mensajeria.colas

  consumir_cola = {
    reservas       = [{ acciones = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], recursos = [local.colas["reservas"].arn] }]
    resultados     = [{ acciones = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], recursos = [local.colas["resultados"].arn] }]
    notificaciones = [{ acciones = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], recursos = [local.colas["notificaciones"].arn] }]
  }
}

module "fn_buscar_equipos" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-buscar-equipos"
  codigo = "${local.codigo}/buscar-equipos"
  capas  = [aws_lambda_layer_version.comun.arn]

  variables = merge(local.variables_bd, {
    BUCKET_FOTOS = module.almacenamiento.bucket_fotos
  })

  permisos = concat(local.permiso_bd, [
    { acciones = ["s3:GetObject"], recursos = ["${module.almacenamiento.bucket_fotos_arn}/equipos/*"] },
  ])
}

module "fn_publicar_equipo" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-publicar-equipo"
  codigo = "${local.codigo}/publicar-equipo"
  capas  = [aws_lambda_layer_version.comun.arn]

  variables = merge(local.variables_bd, {
    TABLA_TELEMETRIA = module.telemetria.tabla_nombre
  })

  permisos = concat(local.permiso_bd, [
    { acciones = ["dynamodb:PutItem"], recursos = [module.telemetria.tabla_arn] },
  ])
}

module "fn_subir_foto" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-subir-foto"
  codigo = "${local.codigo}/subir-foto"
  capas  = [aws_lambda_layer_version.comun.arn]

  variables = merge(local.variables_bd, {
    BUCKET_FOTOS = module.almacenamiento.bucket_fotos
  })

  permisos = concat(local.permiso_bd, [
    { acciones = ["s3:PutObject"], recursos = ["${module.almacenamiento.bucket_fotos_arn}/equipos/*"] },
  ])
}

module "fn_ver_disponibilidad" {
  source    = "./modules/funcion"
  nombre    = "${local.nombre}-ver-disponibilidad"
  codigo    = "${local.codigo}/ver-disponibilidad"
  capas     = [aws_lambda_layer_version.comun.arn]
  variables = local.variables_bd
  permisos  = local.permiso_bd
}

module "fn_crear_reserva" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-crear-reserva"
  codigo = "${local.codigo}/crear-reserva"
  capas  = [aws_lambda_layer_version.comun.arn]

  variables = merge(local.variables_bd, {
    COLA_RESERVAS_URL = local.colas["reservas"].url
  })

  permisos = concat(local.permiso_bd, [
    { acciones = ["sqs:SendMessage"], recursos = [local.colas["reservas"].arn] },
  ])
}

module "fn_cobrar_reserva" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-cobrar-reserva"
  codigo = "${local.codigo}/cobrar-reserva"
  tiempo = 30

  variables = {
    COLA_RESULTADOS_URL  = local.colas["resultados"].url
    SECRETO_PASARELA_ARN = module.secretos.pasarela_arn
  }

  permisos = concat(local.consumir_cola["reservas"], [
    { acciones = ["sqs:SendMessage"], recursos = [local.colas["resultados"].arn] },
    { acciones = ["secretsmanager:GetSecretValue"], recursos = [module.secretos.pasarela_arn] },
  ])
}

module "fn_confirmar_reserva" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-confirmar-reserva"
  codigo = "${local.codigo}/confirmar-reserva"
  capas  = [aws_lambda_layer_version.comun.arn]
  tiempo = 30

  variables = merge(local.variables_bd, {
    COLA_NOTIFICACIONES_URL = local.colas["notificaciones"].url
  })

  permisos = concat(local.permiso_bd, local.consumir_cola["resultados"], [
    { acciones = ["sqs:SendMessage"], recursos = [local.colas["notificaciones"].arn] },
  ])
}

module "fn_enviar_correo" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-enviar-correo"
  codigo = "${local.codigo}/enviar-correo"
  capas  = [aws_lambda_layer_version.comun.arn]
  tiempo = 30

  variables = merge(local.variables_bd, {
    COLA_NOTIFICACIONES_URL = local.colas["notificaciones"].url
    REMITENTE               = module.mensajeria.remitente
  })

  permisos = concat(local.permiso_bd, local.consumir_cola["notificaciones"], [
    { acciones = ["sqs:SendMessage"], recursos = [local.colas["notificaciones"].arn] },
    {
      acciones = ["ses:SendEmail"]
      recursos = ["*"]
      condiciones = [
        { test = "StringEquals", variable = "ses:FromAddress", valores = [module.mensajeria.remitente] },
      ]
    },
  ])
}

module "fn_procesar_telemetria" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-procesar-telemetria"
  codigo = "${local.codigo}/procesar-telemetria"
  capas  = [aws_lambda_layer_version.comun.arn]
  tiempo = 60

  variables = {
    TABLA_TELEMETRIA          = module.telemetria.tabla_nombre
    TOPICO_ALERTAS_ARN        = module.mensajeria.topico_alertas_arn
    UMBRAL_SIN_SENAL_SEGUNDOS = tostring(var.umbral_sin_senal_segundos)
    RETENCION_DIAS            = tostring(var.retencion_puntos_dias)
  }

  permisos = [
    { acciones = ["dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:PutItem"], recursos = [module.telemetria.tabla_arn] },
    { acciones = ["sns:Publish"], recursos = [module.mensajeria.topico_alertas_arn] },
    {
      acciones = ["kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:ListShards"]
      recursos = [module.telemetria.stream_arn]
    },
  ]
}

module "fn_consultar_telemetria" {
  source = "./modules/funcion"
  nombre = "${local.nombre}-consultar-telemetria"
  codigo = "${local.codigo}/consultar-telemetria"
  capas  = [aws_lambda_layer_version.comun.arn]

  variables = merge(local.variables_bd, {
    TABLA_TELEMETRIA = module.telemetria.tabla_nombre
  })

  permisos = concat(local.permiso_bd, [
    { acciones = ["dynamodb:GetItem", "dynamodb:Query"], recursos = [module.telemetria.tabla_arn] },
  ])
}
