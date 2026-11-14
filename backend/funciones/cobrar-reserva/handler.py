import json
import logging
import os
import urllib.error
import urllib.request

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

COLA_RESULTADOS = os.environ["COLA_RESULTADOS_URL"]
SECRETO_PASARELA = os.environ["SECRETO_PASARELA_ARN"]
TIEMPO_ESPERA_S = 15

_sqs = boto3.client("sqs")
_secretos = boto3.client("secretsmanager")
_credencial = None


def _obtener_credencial():
    global _credencial
    if _credencial is None:
        valor = _secretos.get_secret_value(SecretId=SECRETO_PASARELA)["SecretString"]
        _credencial = json.loads(valor)
    return _credencial


def _cobrar(reserva):
    credencial = _obtener_credencial()
    solicitud = urllib.request.Request(
        f"{credencial['url_base'].rstrip('/')}/cobros",
        data=json.dumps(
            {
                "referencia": reserva["reservaId"],
                "monto": round(reserva["total"] * 100),
                "moneda": reserva.get("moneda", "PEN"),
            }
        ).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {credencial['api_key']}",
            "Idempotency-Key": reserva["reservaId"],
        },
    )
    try:
        with urllib.request.urlopen(solicitud, timeout=TIEMPO_ESPERA_S) as respuesta:
            cuerpo = json.loads(respuesta.read() or "{}")
            return {"resultado": "aprobado", "referenciaPago": str(cuerpo.get("id", reserva["reservaId"]))}
    except urllib.error.HTTPError as error:
        if 400 <= error.code < 500 and error.code not in (408, 409, 429):
            return {"resultado": "rechazado", "referenciaPago": None}
        raise


def _procesar(registro):
    reserva = json.loads(registro["body"])
    resultado = _cobrar(reserva)
    _sqs.send_message(
        QueueUrl=COLA_RESULTADOS,
        MessageBody=json.dumps({"reservaId": reserva["reservaId"], **resultado}),
    )


def manejar_evento(evento, contexto):
    fallidos = []
    for registro in evento["Records"]:
        try:
            _procesar(registro)
        except Exception:
            logger.exception("Cobro no completado para el mensaje %s", registro["messageId"])
            fallidos.append({"itemIdentifier": registro["messageId"]})
    return {"batchItemFailures": fallidos}
