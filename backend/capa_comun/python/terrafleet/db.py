import os

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError


class ErrorBaseDatos(Exception):
    pass


class RestriccionViolada(Exception):
    pass


class Resultado:
    def __init__(self, filas):
        self.filas = filas


_cliente = boto3.client(
    "rds-data",
    config=Config(connect_timeout=2, read_timeout=4, retries={"max_attempts": 1}),
)


def _parametro(nombre, valor):
    if valor is None:
        return {"name": nombre, "value": {"isNull": True}}
    if isinstance(valor, bool):
        return {"name": nombre, "value": {"booleanValue": valor}}
    if isinstance(valor, int):
        return {"name": nombre, "value": {"longValue": valor}}
    if isinstance(valor, float):
        return {"name": nombre, "value": {"doubleValue": valor}}
    return {"name": nombre, "value": {"stringValue": str(valor)}}


def _celda(celda):
    if celda.get("isNull"):
        return None
    return next(iter(celda.values()))


def ejecutar(sql, parametros=None):
    try:
        respuesta = _cliente.execute_statement(
            resourceArn=os.environ["DB_CLUSTER_ARN"],
            secretArn=os.environ["DB_SECRET_ARN"],
            database=os.environ["DB_NOMBRE"],
            sql=sql,
            parameters=[_parametro(k, v) for k, v in (parametros or {}).items()],
            includeResultMetadata=True,
        )
    except ClientError as error:
        mensaje = error.response.get("Error", {}).get("Message", "")
        if "violates" in mensaje:
            raise RestriccionViolada(mensaje) from error
        raise ErrorBaseDatos(mensaje) from error
    except BotoCoreError as error:
        raise ErrorBaseDatos(str(error)) from error
    columnas = [c["name"] for c in respuesta.get("columnMetadata", [])]
    filas = [
        {columna: _celda(celda) for columna, celda in zip(columnas, registro)}
        for registro in respuesta.get("records", [])
    ]
    return Resultado(filas)
