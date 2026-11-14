from terrafleet.http import ErrorHttp

ROL_ADMIN = "administradores"
ROL_EMPRESA = "empresas"
ROL_CLIENTE = "clientes"


def usuario(evento):
    claims = (evento.get("requestContext") or {}).get("authorizer", {}).get("claims") or {}
    if not claims.get("sub"):
        raise ErrorHttp(401, "No autenticado")
    grupos = claims.get("cognito:groups") or ""
    if isinstance(grupos, str):
        grupos = grupos.strip("[]").replace(",", " ").split()
    if ROL_ADMIN in grupos:
        rol = ROL_ADMIN
    elif ROL_EMPRESA in grupos:
        rol = ROL_EMPRESA
    else:
        rol = ROL_CLIENTE
    return {
        "id": claims["sub"],
        "correo": claims.get("email"),
        "rol": rol,
        "empresa_id": claims.get("custom:empresa_id") or None,
    }


def exigir_rol(datos_usuario, *roles):
    if datos_usuario["rol"] not in roles:
        raise ErrorHttp(403, "No tiene permisos para esta operación")
