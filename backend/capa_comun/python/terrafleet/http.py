import functools
import json
import logging

from terrafleet.db import ErrorBaseDatos, RestriccionViolada
from terrafleet.serializacion import a_json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

LIMITE_CUERPO_BYTES = 50 * 1024


class ErrorHttp(Exception):
    def __init__(self, estado, mensaje):
        super().__init__(mensaje)
        self.estado = estado
        self.mensaje = mensaje


def respuesta(estado, cuerpo, cabeceras=None):
    return {
        "statusCode": estado,
        "headers": {"Content-Type": "application/json", **(cabeceras or {})},
        "body": a_json(cuerpo),
    }


def cuerpo_json(evento):
    crudo = evento.get("body") or ""
    if len(crudo.encode("utf-8")) > LIMITE_CUERPO_BYTES:
        raise ErrorHttp(413, "El cuerpo supera el tamaño permitido")
    try:
        datos = json.loads(crudo)
    except json.JSONDecodeError as error:
        raise ErrorHttp(400, "El cuerpo no es un JSON válido") from error
    if not isinstance(datos, dict):
        raise ErrorHttp(400, "El cuerpo debe ser un objeto JSON")
    return datos


def texto(datos, campo, maximo, obligatorio=True):
    valor = datos.get(campo)
    if valor is None or valor == "":
        if obligatorio:
            raise ErrorHttp(400, f"Falta el campo {campo}")
        return None
    if not isinstance(valor, str) or len(valor.strip()) == 0 or len(valor) > maximo:
        raise ErrorHttp(400, f"El campo {campo} no es válido")
    return valor.strip()


def parametro(evento, nombre):
    return (evento.get("queryStringParameters") or {}).get(nombre)


def ruta(evento, nombre):
    valor = (evento.get("pathParameters") or {}).get(nombre)
    if not valor:
        raise ErrorHttp(400, f"Falta el parámetro {nombre}")
    return valor


def manejar(funcion):
    @functools.wraps(funcion)
    def envoltura(evento, contexto):
        try:
            return funcion(evento, contexto)
        except ErrorHttp as error:
            return respuesta(error.estado, {"mensaje": error.mensaje})
        except RestriccionViolada:
            return respuesta(409, {"mensaje": "La operación entra en conflicto con datos existentes"})
        except ErrorBaseDatos:
            logger.exception("Base de datos no disponible")
            return respuesta(
                503,
                {"mensaje": "Servicio temporalmente no disponible"},
                {"Retry-After": "5"},
            )
        except Exception:
            logger.exception("Error no controlado")
            return respuesta(500, {"mensaje": "Error interno"})

    return envoltura
