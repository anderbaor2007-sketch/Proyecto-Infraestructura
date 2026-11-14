import base64
import json
import logging
import math
import os

import boto3
from botocore.exceptions import ClientError

from terrafleet.serializacion import a_decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

NOMBRE_TABLA = os.environ["TABLA_TELEMETRIA"]
TOPICO_ALERTAS = os.environ["TOPICO_ALERTAS_ARN"]
UMBRAL_SIN_SENAL_MS = int(os.environ["UMBRAL_SIN_SENAL_SEGUNDOS"]) * 1000
RETENCION_SEGUNDOS = int(os.environ["RETENCION_DIAS"]) * 86400
TAMANO_LOTE_LECTURA = 50
ULTIMA = 0
GEOCERCA = -1

_dynamo = boto3.resource("dynamodb")
_tabla = _dynamo.Table(NOMBRE_TABLA)
_sns = boto3.client("sns")


def _numero(valor, minimo, maximo):
    if isinstance(valor, bool) or not isinstance(valor, (int, float)):
        return None
    return float(valor) if minimo <= valor <= maximo else None


def _validar(evento):
    equipo = evento.get("equipoId")
    empresa = evento.get("empresaId")
    marca = evento.get("timestamp")
    latitud = _numero(evento.get("latitud"), -90, 90)
    longitud = _numero(evento.get("longitud"), -180, 180)
    velocidad = _numero(evento.get("velocidad", 0), 0, 300)
    if not isinstance(equipo, str) or not equipo or not isinstance(empresa, str) or not empresa:
        return None
    if isinstance(marca, bool) or not isinstance(marca, int) or marca <= 0:
        return None
    if latitud is None or longitud is None or velocidad is None:
        return None
    return {
        "equipoId": equipo,
        "empresaId": empresa,
        "timestamp": marca,
        "latitud": latitud,
        "longitud": longitud,
        "velocidad": velocidad,
        "motor": str(evento.get("motor", "desconocido"))[:20],
    }


def _decodificar(registro):
    try:
        bruto = json.loads(base64.b64decode(registro["kinesis"]["data"]))
    except (ValueError, KeyError):
        logger.warning("Evento descartado: no es JSON")
        return None
    valido = _validar(bruto) if isinstance(bruto, dict) else None
    if valido is None:
        logger.warning("Evento descartado: formato o coordenadas inválidas")
    return valido


def _distancia_km(lat1, lon1, lat2, lon2):
    radio = 6371.0088
    f1, f2 = math.radians(lat1), math.radians(lat2)
    df, dl = f2 - f1, math.radians(lon2 - lon1)
    a = math.sin(df / 2) ** 2 + math.cos(f1) * math.cos(f2) * math.sin(dl / 2) ** 2
    return 2 * radio * math.asin(math.sqrt(a))


def _cargar_estados(equipos):
    estados = {equipo: {"ultima": None, "geocerca": None, "modificado": False} for equipo in equipos}
    pendientes = list(estados)
    for inicio in range(0, len(pendientes), TAMANO_LOTE_LECTURA):
        claves = []
        for equipo in pendientes[inicio:inicio + TAMANO_LOTE_LECTURA]:
            claves.append({"equipoId": equipo, "timestamp": ULTIMA})
            claves.append({"equipoId": equipo, "timestamp": GEOCERCA})
        respuesta = _dynamo.batch_get_item(RequestItems={NOMBRE_TABLA: {"Keys": claves}})
        if respuesta.get("UnprocessedKeys"):
            raise RuntimeError("Lectura parcial del estado de los equipos")
        for item in respuesta["Responses"][NOMBRE_TABLA]:
            destino = "ultima" if int(item["timestamp"]) == ULTIMA else "geocerca"
            estados[item["equipoId"]][destino] = item
    return estados


def _evaluar_alertas(dato, ultima, geocerca):
    alertas = []
    if ultima is not None:
        silencio = dato["timestamp"] - int(ultima["ultimo_ts"])
        if silencio > UMBRAL_SIN_SENAL_MS:
            alertas.append(("sin_senal", {"segundosSinEventos": silencio // 1000}))
    fuera = False
    if geocerca is not None:
        distancia = _distancia_km(
            dato["latitud"], dato["longitud"], float(geocerca["latitud"]), float(geocerca["longitud"])
        )
        radio = float(geocerca["radioKm"])
        fuera = distancia > radio
        estaba_fuera = bool(ultima is not None and ultima.get("fuera_geocerca"))
        if fuera and not estaba_fuera:
            alertas.append(("geocerca", {"distanciaKm": round(distancia, 3), "radioKm": radio}))
    return alertas, fuera


def _publicar(alerta, detalle, dato):
    _sns.publish(
        TopicArn=TOPICO_ALERTAS,
        Message=json.dumps(
            {
                "tipo": "alerta",
                "alerta": alerta,
                "equipoId": dato["equipoId"],
                "empresaId": dato["empresaId"],
                "timestamp": dato["timestamp"],
                "detalle": detalle,
            }
        ),
    )


def _guardar_punto(dato):
    item = {**dato, "ttl": dato["timestamp"] // 1000 + RETENCION_SEGUNDOS}
    try:
        _tabla.put_item(Item=a_decimal(item), ConditionExpression="attribute_not_exists(equipoId)")
    except ClientError as error:
        if error.response["Error"]["Code"] != "ConditionalCheckFailedException":
            raise


def _procesar(dato, estado):
    ultima = estado["ultima"]
    es_nuevo = ultima is None or dato["timestamp"] > int(ultima["ultimo_ts"])
    fuera = False
    if es_nuevo:
        alertas, fuera = _evaluar_alertas(dato, ultima, estado["geocerca"])
        for alerta, detalle in alertas:
            _publicar(alerta, detalle, dato)
    _guardar_punto(dato)
    if es_nuevo:
        estado["ultima"] = {
            "equipoId": dato["equipoId"],
            "timestamp": ULTIMA,
            "empresaId": dato["empresaId"],
            "latitud": dato["latitud"],
            "longitud": dato["longitud"],
            "velocidad": dato["velocidad"],
            "motor": dato["motor"],
            "ultimo_ts": dato["timestamp"],
            "fuera_geocerca": fuera,
        }
        estado["modificado"] = True


def _guardar_ultimas(estados):
    for estado in estados.values():
        if estado["modificado"]:
            _tabla.put_item(Item=a_decimal(estado["ultima"]))


def manejar_evento(evento, contexto):
    datos = []
    for registro in evento["Records"]:
        dato = _decodificar(registro)
        if dato is not None:
            datos.append((registro["kinesis"]["sequenceNumber"], dato))

    estados = _cargar_estados({dato["equipoId"] for _, dato in datos})
    fallo = None
    try:
        for secuencia, dato in datos:
            try:
                _procesar(dato, estados[dato["equipoId"]])
            except Exception:
                logger.exception("Evento no procesado")
                fallo = secuencia
                break
    finally:
        _guardar_ultimas(estados)

    return {"batchItemFailures": [{"itemIdentifier": fallo}] if fallo else []}
