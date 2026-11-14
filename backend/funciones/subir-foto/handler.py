import os
import uuid

import boto3
from botocore.config import Config

from terrafleet import db
from terrafleet.auth import ROL_ADMIN, ROL_EMPRESA, exigir_rol, usuario
from terrafleet.http import ErrorHttp, cuerpo_json, manejar, respuesta, ruta, texto

BUCKET_FOTOS = os.environ["BUCKET_FOTOS"]
TIPOS = {"image/jpeg": "jpg", "image/png": "png"}
LIMITE_BYTES = 1024 * 1024

_s3 = boto3.client(
    "s3",
    region_name=os.environ["AWS_REGION"],
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)


@manejar
def manejar_evento(evento, contexto):
    datos_usuario = usuario(evento)
    exigir_rol(datos_usuario, ROL_EMPRESA, ROL_ADMIN)
    equipo_id = ruta(evento, "id")
    tipo = texto(cuerpo_json(evento), "contentType", 30)
    if tipo not in TIPOS:
        raise ErrorHttp(400, "Solo se admiten imágenes JPEG o PNG")

    equipo = db.ejecutar(
        "SELECT CAST(empresa_id AS text) AS empresa_id FROM equipos WHERE id = CAST(:id AS uuid)",
        {"id": equipo_id},
    )
    if not equipo.filas:
        raise ErrorHttp(404, "El equipo no existe")
    if datos_usuario["rol"] != ROL_ADMIN and equipo.filas[0]["empresa_id"] != datos_usuario["empresa_id"]:
        raise ErrorHttp(403, "El equipo pertenece a otra empresa")

    clave = f"equipos/{equipo_id}/{uuid.uuid4().hex}.{TIPOS[tipo]}"
    autorizacion = _s3.generate_presigned_post(
        Bucket=BUCKET_FOTOS,
        Key=clave,
        Fields={"Content-Type": tipo},
        Conditions=[{"Content-Type": tipo}, ["content-length-range", 1, LIMITE_BYTES]],
        ExpiresIn=300,
    )
    db.ejecutar(
        "UPDATE equipos SET foto_clave = :clave WHERE id = CAST(:id AS uuid)",
        {"clave": clave, "id": equipo_id},
    )
    return respuesta(200, {"url": autorizacion["url"], "campos": autorizacion["fields"], "clave": clave})
