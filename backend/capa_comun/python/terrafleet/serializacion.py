import json
from decimal import Decimal


def a_decimal(valor):
    return json.loads(json.dumps(valor), parse_float=Decimal)


def _normalizar(valor):
    if isinstance(valor, Decimal):
        return int(valor) if valor == valor.to_integral_value() else float(valor)
    return str(valor)


def a_json(valor):
    return json.dumps(valor, default=_normalizar, ensure_ascii=False)
