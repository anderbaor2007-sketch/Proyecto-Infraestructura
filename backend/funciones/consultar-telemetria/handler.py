import os
import time

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import BotoCoreError, ClientError

from terrafleet import db
from terrafleet.auth import ROL_ADMIN, usuario
from terrafleet.http import ErrorHttp, manejar, parametro, respuesta, ruta

VENTANA_MAXIMA_MS = 24 * 3600 * 1000

_tabla = boto3.resource("dynamodb").Table(os.environ["TABLA_TELEMETRIA"])


def _autorizar(datos_usuario, equipo_id):
    filas = db.ejecutar(
        "SELECT CAST(e.empresa_id AS text) AS empresa_id, EXISTS ("
        "SELECT 1 FROM reservas r WHERE r.equipo_id = e.id AND r.cliente_id = :cliente "
        "AND r.estado = 'confirmada' AND current_date BETWEEN r.fecha_inicio AND r.fecha_fin"
        ") AS cliente_activo FROM equipos e WHERE e.id = CAST(:id AS uuid)",
        {"id": equipo_id, "cliente": datos_usuario["id"]},
    ).filas
    if not filas:
        raise ErrorHttp(404, "El equipo no existe")
    es_propietario = datos_usuario["empresa_id"] == filas[0]["empresa_id"]
    if datos_usuario["rol"] != ROL_ADMIN and not es_propietario and not filas[0]["cliente_activo"]:
        raise ErrorHttp(403, "No tiene permisos sobre este equipo")


def _entero(evento, nombre, defecto):
    valor = parametro(evento, nombre)
    if valor is None:
        return defecto
    if not valor.isdigit():
        raise ErrorHttp(400, f"{nombre} debe ser una marca de tiempo en milisegundos")
    return int(valor)


def _ultima(equipo_id):
    item = _tabla.get_item(Key={"equipoId": equipo_id, "timestamp": 0}).get("Item")
    if item is None:
        raise ErrorHttp(404, "El equipo aún no reporta posición")
    return respuesta(
        200,
        {
            "equipoId": equipo_id,
            "latitud": item["latitud"],
            "longitud": item["longitud"],
            "velocidad": item["velocidad"],
            "motor": item["motor"],
            "timestamp": item["ultimo_ts"],
            "fueraGeocerca": item.get("fuera_geocerca", False),
        },
        {"Cache-Control": "no-store"},
    )


def _recorrido(evento, equipo_id):
    ahora = int(time.time() * 1000)
    hasta = _entero(evento, "hasta", ahora)
    desde = max(_entero(evento, "desde", hasta - VENTANA_MAXIMA_MS), 1)
    if hasta < desde:
        raise ErrorHttp(400, "hasta no puede ser anterior a desde")
    if hasta - desde > VENTANA_MAXIMA_MS:
        raise ErrorHttp(400, "La ventana no puede superar 24 horas")

    consulta = {
        "KeyConditionExpression": Key("equipoId").eq(equipo_id) & Key("timestamp").between(desde, hasta),
        "ProjectionExpression": "latitud, longitud, velocidad, #t",
        "ExpressionAttributeNames": {"#t": "timestamp"},
    }
    puntos = []
    while True:
        pagina = _tabla.query(**consulta)
        puntos.extend(pagina["Items"])
        if "LastEvaluatedKey" not in pagina:
            break
        consulta["ExclusiveStartKey"] = pagina["LastEvaluatedKey"]
    return respuesta(200, {"equipoId": equipo_id, "desde": desde, "hasta": hasta, "puntos": puntos})


@manejar
def manejar_evento(evento, contexto):
    datos_usuario = usuario(evento)
    equipo_id = ruta(evento, "id")
    _autorizar(datos_usuario, equipo_id)
    try:
        if evento["resource"].endswith("/ultima"):
            return _ultima(equipo_id)
        return _recorrido(evento, equipo_id)
    except (ClientError, BotoCoreError) as error:
        raise ErrorHttp(503, "Servicio de telemetría temporalmente no disponible") from error
