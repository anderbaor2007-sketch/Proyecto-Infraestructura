import os

import boto3
from botocore.config import Config

from terrafleet import db
from terrafleet.http import ErrorHttp, manejar, parametro, respuesta

BUCKET_FOTOS = os.environ["BUCKET_FOTOS"]
TAMANO_PAGINA = 50

_s3 = boto3.client(
    "s3",
    region_name=os.environ["AWS_REGION"],
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)


def _filtros(evento):
    condiciones = ["activo"]
    parametros = {}
    for nombre in ("ciudad", "categoria", "marca"):
        valor = parametro(evento, nombre)
        if valor:
            condiciones.append(f"lower({nombre}) = lower(:{nombre})")
            parametros[nombre] = valor.strip()
    tarifa_max = parametro(evento, "tarifaMax")
    if tarifa_max:
        try:
            parametros["tarifa_max"] = float(tarifa_max)
        except ValueError as error:
            raise ErrorHttp(400, "tarifaMax no es válida") from error
        condiciones.append("tarifa_dia <= CAST(:tarifa_max AS numeric)")
    return condiciones, parametros


def _pagina(evento):
    valor = parametro(evento, "pagina") or "0"
    if not valor.isdigit():
        raise ErrorHttp(400, "pagina no es válida")
    return int(valor)


def _foto(clave):
    if not clave:
        return None
    return _s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET_FOTOS, "Key": clave},
        ExpiresIn=900,
    )


@manejar
def manejar_evento(evento, contexto):
    condiciones, parametros = _filtros(evento)
    pagina = _pagina(evento)
    resultado = db.ejecutar(
        "SELECT CAST(id AS text) AS id, nombre, categoria, marca, modelo, ciudad, "
        "CAST(tarifa_dia AS float8) AS tarifa_dia, foto_clave "
        "FROM equipos WHERE " + " AND ".join(condiciones) + " "
        "ORDER BY tarifa_dia, id "
        f"LIMIT {TAMANO_PAGINA} OFFSET {pagina * TAMANO_PAGINA}",
        parametros,
    )
    equipos = []
    for fila in resultado.filas:
        clave = fila.pop("foto_clave")
        fila["fotoUrl"] = _foto(clave)
        fila["tarifaDia"] = fila.pop("tarifa_dia")
        equipos.append(fila)
    return respuesta(200, {"equipos": equipos, "pagina": pagina})
