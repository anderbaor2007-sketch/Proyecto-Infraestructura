import json
import os
from datetime import date

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from terrafleet import db
from terrafleet.auth import usuario
from terrafleet.http import ErrorHttp, cuerpo_json, manejar, respuesta, texto

COLA_RESERVAS = os.environ["COLA_RESERVAS_URL"]
MAXIMO_DIAS = 90

_sqs = boto3.client("sqs")


def _fecha(datos, campo):
    valor = texto(datos, campo, 10)
    try:
        return date.fromisoformat(valor)
    except ValueError as error:
        raise ErrorHttp(400, f"{campo} no es una fecha válida (AAAA-MM-DD)") from error


def _liberar(reserva_id):
    try:
        db.ejecutar(
            "UPDATE reservas SET estado = 'cancelada', actualizado_en = now() "
            "WHERE id = CAST(:id AS uuid) AND estado = 'pendiente'",
            {"id": reserva_id},
        )
    except db.ErrorBaseDatos:
        pass


@manejar
def manejar_evento(evento, contexto):
    datos_usuario = usuario(evento)
    datos = cuerpo_json(evento)
    equipo_id = texto(datos, "equipoId", 36)
    inicio = _fecha(datos, "fechaInicio")
    fin = _fecha(datos, "fechaFin")
    if inicio < date.today():
        raise ErrorHttp(400, "fechaInicio no puede estar en el pasado")
    if fin < inicio:
        raise ErrorHttp(400, "fechaFin no puede ser anterior a fechaInicio")
    if (fin - inicio).days >= MAXIMO_DIAS:
        raise ErrorHttp(400, f"La reserva no puede superar {MAXIMO_DIAS} días")
    if not datos_usuario["correo"]:
        raise ErrorHttp(400, "El usuario no tiene un correo verificado")

    creada = db.ejecutar(
        "INSERT INTO reservas (equipo_id, cliente_id, cliente_correo, fecha_inicio, fecha_fin, total) "
        "SELECT e.id, :cliente, :correo, CAST(:inicio AS date), CAST(:fin AS date), "
        "e.tarifa_dia * (CAST(:fin AS date) - CAST(:inicio AS date) + 1) "
        "FROM equipos e WHERE e.id = CAST(:equipo AS uuid) AND e.activo "
        "RETURNING CAST(id AS text) AS id, CAST(total AS float8) AS total",
        {
            "cliente": datos_usuario["id"],
            "correo": datos_usuario["correo"],
            "inicio": inicio.isoformat(),
            "fin": fin.isoformat(),
            "equipo": equipo_id,
        },
    )
    if not creada.filas:
        raise ErrorHttp(404, "El equipo no existe")
    reserva = creada.filas[0]

    try:
        _sqs.send_message(
            QueueUrl=COLA_RESERVAS,
            MessageBody=json.dumps({"reservaId": reserva["id"], "total": reserva["total"], "moneda": "PEN"}),
        )
    except (ClientError, BotoCoreError) as error:
        _liberar(reserva["id"])
        raise ErrorHttp(503, "No se pudo encolar el cobro; la reserva fue cancelada") from error

    return respuesta(201, {"reservaId": reserva["id"], "estado": "pendiente", "total": reserva["total"]})
