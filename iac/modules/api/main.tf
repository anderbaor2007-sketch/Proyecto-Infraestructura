data "aws_region" "actual" {}

resource "aws_api_gateway_rest_api" "this" {
  name = "${var.nombre}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.nombre}-cognito"
  rest_api_id     = aws_api_gateway_rest_api.this.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [var.cognito_pool_arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_resource" "equipos" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "equipos"
}

resource "aws_api_gateway_resource" "equipo" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.equipos.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "foto" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.equipo.id
  path_part   = "foto"
}

resource "aws_api_gateway_resource" "disponibilidad" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "disponibilidad"
}

resource "aws_api_gateway_resource" "disponibilidad_equipo" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.disponibilidad.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "reservas" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "reservas"
}

resource "aws_api_gateway_resource" "telemetria" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "telemetria"
}

resource "aws_api_gateway_resource" "telemetria_equipo" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.telemetria.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "ultima" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.telemetria_equipo.id
  path_part   = "ultima"
}

resource "aws_api_gateway_resource" "recorrido" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.telemetria_equipo.id
  path_part   = "ruta"
}

locals {
  rutas = {
    buscar_equipos     = { metodo = "GET", recurso = aws_api_gateway_resource.equipos.id, funcion = "buscar-equipos", permiso = "/equipos" }
    publicar_equipo    = { metodo = "POST", recurso = aws_api_gateway_resource.equipos.id, funcion = "publicar-equipo", permiso = "/equipos" }
    subir_foto         = { metodo = "POST", recurso = aws_api_gateway_resource.foto.id, funcion = "subir-foto", permiso = "/equipos/*/foto" }
    ver_disponibilidad = { metodo = "GET", recurso = aws_api_gateway_resource.disponibilidad_equipo.id, funcion = "ver-disponibilidad", permiso = "/disponibilidad/*" }
    crear_reserva      = { metodo = "POST", recurso = aws_api_gateway_resource.reservas.id, funcion = "crear-reserva", permiso = "/reservas" }
    telemetria_ultima  = { metodo = "GET", recurso = aws_api_gateway_resource.ultima.id, funcion = "consultar-telemetria", permiso = "/telemetria/*/ultima" }
    telemetria_ruta    = { metodo = "GET", recurso = aws_api_gateway_resource.recorrido.id, funcion = "consultar-telemetria", permiso = "/telemetria/*/ruta" }
  }
}

resource "aws_api_gateway_method" "this" {
  for_each      = local.rutas
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = each.value.recurso
  http_method   = each.value.metodo
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "this" {
  for_each                = local.rutas
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = each.value.recurso
  http_method             = aws_api_gateway_method.this[each.key].http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.funciones[each.value.funcion].invoke_arn
}

resource "aws_lambda_permission" "api" {
  for_each      = local.rutas
  statement_id  = "api-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = var.funciones[each.value.funcion].nombre
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/${each.value.metodo}${each.value.permiso}"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redespliegue = sha1(jsonencode([
      aws_api_gateway_method.this,
      aws_api_gateway_integration.this,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.etapa
}

resource "aws_api_gateway_method_settings" "todas" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.limite_tasa
    throttling_burst_limit = var.limite_rafaga
    metrics_enabled        = true
  }
}
