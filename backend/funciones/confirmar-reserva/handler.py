import json
import logging
import os

import boto3

from terrafleet import db

logger = logging.getLogger()
logger.setLevel(logging.INFO)

COLA_NOTIFICACIONES = os.environ["COLA_NOTIFICACIONES_URL"]
ESTADOS = {"aprobado": "confirmada", "rechazado": "rechazada"}

_sqs = boto3.client("sqs")


def _aplicar(resultado):
    estado = ESTADOS[resultado["resultado"]]
    db.ejecutar(
        "UPDATE reservas SET estado = :estado, referencia_pago = :referencia, actualizado_en = now() "
        "WHERE id = CAST(:id AS uuid) AND estado = 'pendiente'",
        {"estado": estado, "referencia": resultado.get("referenciaPago"), "id": resultado["reservaId"]},
    )
    return estado


def _detalle(reserva_id):
    filas = db.ejecutar(
        "SELECT r.estado, r.cliente_correo, em.correo AS empresa_correo, e.nombre AS equipo, "
        "CAST(r.fecha_inicio AS text) AS inicio, CAST(r.fecha_fin AS text) AS fin, "
        "CAST(r.total AS float8) AS total "
        "FROM reservas r JOIN equipos e ON e.id = r.equipo_id JOIN empresas em ON em.id = e.empresa_id "
        "WHERE r.id = CAST(:id AS uuid)",
        {"id": reserva_id},
    ).filas
    return filas[0] if filas else None


def _aviso(detalle):
    confirmada = detalle["estado"] == "confirmada"
    asunto = "Reserva confirmada" if confirmada else "Reserva rechazada"
    cuerpo = (
        f"Equipo: {detalle['equipo']}\n"
        f"Periodo: {detalle['inicio']} al {detalle['fin']}\n"
        f"Total: S/ {detalle['total']:.2f}\n"
        f"Estado: {detalle['estado']}"
    )
    return {
        "tipo": "reserva",
        "asunto": asunto,
        "cuerpo": cuerpo,
        "destinatarios": [detalle["cliente_correo"], detalle["empresa_correo"]],
    }


def _procesar(registro):
    resultado = json.loads(registro["body"])
    estado = _aplicar(resultado)
    detalle = _detalle(resultado["reservaId"])
    if detalle is None or detalle["estado"] != estado:
        logger.warning("Resultado omitido para la reserva %s", resultado["reservaId"])
        return
    _sqs.send_message(QueueUrl=COLA_NOTIFICACIONES, MessageBody=json.dumps(_aviso(detalle)))


def manejar_evento(evento, contexto):
    fallidos = []
    for registro in evento["Records"]:
        try:
            _procesar(registro)
        except Exception:
            logger.exception("Confirmación fallida para el mensaje %s", registro["messageId"])
            fallidos.append({"itemIdentifier": registro["messageId"]})
    return {"batchItemFailures": fallidos}
