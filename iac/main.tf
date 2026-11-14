locals {
  nombre     = "${var.proyecto}-${var.entorno}"
  origen_web = var.dominio != "" ? var.dominio : module.frontend.dominio
}

module "red" {
  source = "./modules/red"
  nombre = local.nombre
}

module "autenticacion" {
  source = "./modules/autenticacion"
  nombre = local.nombre
}

module "base_datos" {
  source             = "./modules/base_datos"
  nombre             = local.nombre
  region             = var.region
  subredes_ids       = module.red.subredes_ids
  zonas              = module.red.zonas
  grupo_seguridad_id = module.red.grupo_seguridad_bd_id
  ruta_esquema       = abspath("${path.root}/../database/schema")
  proteger_borrado   = var.proteger_base_datos
}

module "almacenamiento" {
  source                 = "./modules/almacenamiento"
  nombre                 = local.nombre
  origenes_permitidos    = ["https://${local.origen_web}"]
  destruir_con_contenido = var.destruir_con_contenido
}

module "mensajeria" {
  source    = "./modules/mensajeria"
  nombre    = local.nombre
  remitente = var.remitente_ses
}

module "secretos" {
  source = "./modules/secretos"
  nombre = local.nombre
}

module "telemetria" {
  source                 = "./modules/telemetria"
  nombre                 = local.nombre
  region                 = var.region
  dispositivos           = var.dispositivos
  destruir_con_contenido = var.destruir_con_contenido
}

module "api" {
  source           = "./modules/api"
  nombre           = local.nombre
  cognito_pool_arn = module.autenticacion.pool_arn

  funciones = {
    "buscar-equipos"       = { nombre = module.fn_buscar_equipos.nombre, invoke_arn = module.fn_buscar_equipos.invoke_arn }
    "publicar-equipo"      = { nombre = module.fn_publicar_equipo.nombre, invoke_arn = module.fn_publicar_equipo.invoke_arn }
    "subir-foto"           = { nombre = module.fn_subir_foto.nombre, invoke_arn = module.fn_subir_foto.invoke_arn }
    "ver-disponibilidad"   = { nombre = module.fn_ver_disponibilidad.nombre, invoke_arn = module.fn_ver_disponibilidad.invoke_arn }
    "crear-reserva"        = { nombre = module.fn_crear_reserva.nombre, invoke_arn = module.fn_crear_reserva.invoke_arn }
    "consultar-telemetria" = { nombre = module.fn_consultar_telemetria.nombre, invoke_arn = module.fn_consultar_telemetria.invoke_arn }
  }
}

module "frontend" {
  source = "./modules/frontend"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  nombre                 = local.nombre
  dominio_api            = module.api.dominio
  etapa_api              = module.api.etapa
  rutas_api              = ["/equipos*", "/disponibilidad/*", "/reservas*", "/telemetria/*"]
  contenido              = abspath("${path.root}/../frontend")
  alias                  = var.dominio
  certificado_arn        = module.dominio.certificado_arn
  destruir_con_contenido = var.destruir_con_contenido

  configuracion = {
    region     = var.region
    clienteId  = module.autenticacion.cliente_id
    cognitoUrl = "https://cognito-idp.${var.region}.amazonaws.com/"
  }
}

module "dominio" {
  source = "./modules/dominio"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  dominio            = var.dominio
  zona               = var.zona_dns
  cloudfront_dominio = module.frontend.dominio
  cloudfront_zona_id = module.frontend.zona_id
}

module "observabilidad" {
  source                 = "./modules/observabilidad"
  nombre                 = local.nombre
  correo_alarmas         = var.correo_alarmas
  stream_nombre          = module.telemetria.stream_nombre
  api_nombre             = module.api.nombre_api
  etapa_api              = module.api.etapa
  destruir_con_contenido = var.destruir_con_contenido

  funciones = {
    "buscar-equipos"       = module.fn_buscar_equipos.nombre
    "publicar-equipo"      = module.fn_publicar_equipo.nombre
    "subir-foto"           = module.fn_subir_foto.nombre
    "ver-disponibilidad"   = module.fn_ver_disponibilidad.nombre
    "crear-reserva"        = module.fn_crear_reserva.nombre
    "cobrar-reserva"       = module.fn_cobrar_reserva.nombre
    "confirmar-reserva"    = module.fn_confirmar_reserva.nombre
    "enviar-correo"        = module.fn_enviar_correo.nombre
    "procesar-telemetria"  = module.fn_procesar_telemetria.nombre
    "consultar-telemetria" = module.fn_consultar_telemetria.nombre
  }

  colas = {
    for clave, cola in module.mensajeria.colas : clave => cola.nombre
  }
}
