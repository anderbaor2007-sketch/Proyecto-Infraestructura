import json
import logging
import os

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from terrafleet import db

logger = logging.getLogger()
logger.setLevel(logging.INFO)

COLA_NOTIFICACIONES = os.environ["COLA_NOTIFICACIONES_URL"]
REMITENTE = os.environ["REMITENTE"]

_ses = boto3.client("sesv2")
_sqs = boto3.client("sqs")

ASUNTOS = {
    "geocerca": "Alerta: equipo fuera de su geocerca",
    "sin_senal": "Alerta: equipo sin señal",
}


def _correo_empresa(empresa_id):
    filas = db.ejecutar(
        "SELECT correo FROM empresas WHERE id = CAST(:id AS uuid)",
        {"id": empresa_id},
    ).filas
    return [filas[0]["correo"]] if filas else []


def _componer(mensaje):
    if mensaje.get("tipo") != "alerta":
        return mensaje["asunto"], mensaje["cuerpo"], mensaje["destinatarios"]
    cuerpo = (
        f"Equipo: {mensaje['equipoId']}\n"
        f"Evento: {mensaje['alerta']}\n"
        f"Detalle: {json.dumps(mensaje.get('detalle', {}), ensure_ascii=False)}"
    )
    destinatarios = mensaje.get("destinatarios") or _correo_empresa(mensaje["empresaId"])
    return ASUNTOS[mensaje["alerta"]], cuerpo, destinatarios


def _enviar(destinatario, asunto, cuerpo):
    _ses.send_email(
        FromEmailAddress=REMITENTE,
        Destination={"ToAddresses": [destinatario]},
        Content={
            "Simple": {
                "Subject": {"Data": asunto, "Charset": "UTF-8"},
                "Body": {"Text": {"Data": cuerpo, "Charset": "UTF-8"}},
            }
        },
    )


def _procesar(registro):
    mensaje = json.loads(registro["body"])
    asunto, cuerpo, destinatarios = _componer(mensaje)
    pendientes = []
    for destinatario in destinatarios:
        try:
            _enviar(destinatario, asunto, cuerpo)
        except (ClientError, BotoCoreError):
            logger.exception("Fallo el envío a un destinatario")
            pendientes.append(destinatario)
    if not pendientes:
        return
    if len(pendientes) == len(destinatarios):
        raise RuntimeError("No se pudo enviar el aviso a ningún destinatario")
    _sqs.send_message(
        QueueUrl=COLA_NOTIFICACIONES,
        MessageBody=json.dumps({**mensaje, "tipo": "reserva", "asunto": asunto, "cuerpo": cuerpo, "destinatarios": pendientes}),
    )


def manejar_evento(evento, contexto):
    fallidos = []
    for registro in evento["Records"]:
        try:
            _procesar(registro)
        except Exception:
            logger.exception("Aviso no enviado para el mensaje %s", registro["messageId"])
            fallidos.append({"itemIdentifier": registro["messageId"]})
    return {"batchItemFailures": fallidos}
