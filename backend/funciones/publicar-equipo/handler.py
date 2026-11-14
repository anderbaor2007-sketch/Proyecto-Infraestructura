import os

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from terrafleet import db
from terrafleet.auth import ROL_ADMIN, ROL_EMPRESA, exigir_rol, usuario
from terrafleet.http import ErrorHttp, cuerpo_json, manejar, respuesta, texto
from terrafleet.serializacion import a_decimal

_tabla = boto3.resource("dynamodb").Table(os.environ["TABLA_TELEMETRIA"])


def _numero(datos, campo, minimo, maximo, obligatorio=True):
    valor = datos.get(campo)
    if valor is None:
        if obligatorio:
            raise ErrorHttp(400, f"Falta el campo {campo}")
        return None
    if isinstance(valor, bool) or not isinstance(valor, (int, float)) or not minimo <= valor <= maximo:
        raise ErrorHttp(400, f"El campo {campo} no es válido")
    return float(valor)


def _geocerca(datos):
    bruto = datos.get("geocerca")
    if bruto is None:
        return None
    if not isinstance(bruto, dict):
        raise ErrorHttp(400, "El campo geocerca no es válido")
    return {
        "latitud": _numero(bruto, "latitud", -90, 90),
        "longitud": _numero(bruto, "longitud", -180, 180),
        "radioKm": _numero(bruto, "radioKm", 0.01, 500),
    }


def _empresa(datos_usuario, datos):
    if datos_usuario["rol"] == ROL_ADMIN:
        return texto(datos, "empresaId", 36)
    if not datos_usuario["empresa_id"]:
        raise ErrorHttp(403, "El usuario no está asociado a una empresa")
    return datos_usuario["empresa_id"]


@manejar
def manejar_evento(evento, contexto):
    datos_usuario = usuario(evento)
    exigir_rol(datos_usuario, ROL_EMPRESA, ROL_ADMIN)
    datos = cuerpo_json(evento)
    empresa_id = _empresa(datos_usuario, datos)
    nombre = texto(datos, "nombre", 150)
    categoria = texto(datos, "categoria", 60)
    marca = texto(datos, "marca", 60)
    modelo = texto(datos, "modelo", 80, obligatorio=False)
    ciudad = texto(datos, "ciudad", 80)
    descripcion = texto(datos, "descripcion", 2000, obligatorio=False)
    tarifa = _numero(datos, "tarifaDia", 0.01, 1000000)
    geocerca = _geocerca(datos)

    existe = db.ejecutar(
        "SELECT 1 AS ok FROM empresas WHERE id = CAST(:empresa AS uuid)",
        {"empresa": empresa_id},
    )
    if not existe.filas:
        raise ErrorHttp(403, "La empresa no está registrada")

    creado = db.ejecutar(
        "INSERT INTO equipos (empresa_id, nombre, categoria, marca, modelo, ciudad, tarifa_dia, descripcion) "
        "VALUES (CAST(:empresa AS uuid), :nombre, :categoria, :marca, :modelo, :ciudad, "
        "CAST(:tarifa AS numeric), :descripcion) RETURNING CAST(id AS text) AS id",
        {
            "empresa": empresa_id,
            "nombre": nombre,
            "categoria": categoria,
            "marca": marca,
            "modelo": modelo,
            "ciudad": ciudad,
            "tarifa": tarifa,
            "descripcion": descripcion,
        },
    )
    equipo_id = creado.filas[0]["id"]

    if geocerca:
        try:
            _tabla.put_item(
                Item=a_decimal({"equipoId": equipo_id, "timestamp": -1, "empresaId": empresa_id, **geocerca})
            )
        except (ClientError, BotoCoreError) as error:
            db.ejecutar("DELETE FROM equipos WHERE id = CAST(:id AS uuid)", {"id": equipo_id})
            raise ErrorHttp(503, "No se pudo registrar la geocerca; el equipo no fue publicado") from error

    return respuesta(201, {"equipoId": equipo_id})
