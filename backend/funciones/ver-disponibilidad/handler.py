from datetime import date, timedelta

from terrafleet import db
from terrafleet.http import ErrorHttp, manejar, parametro, respuesta, ruta

MAXIMO_DIAS = 90


def _fecha(valor, nombre):
    try:
        return date.fromisoformat(valor)
    except ValueError as error:
        raise ErrorHttp(400, f"{nombre} no es una fecha válida (AAAA-MM-DD)") from error


def _periodo(evento):
    desde = _fecha(parametro(evento, "desde"), "desde") if parametro(evento, "desde") else date.today()
    hasta = _fecha(parametro(evento, "hasta"), "hasta") if parametro(evento, "hasta") else desde + timedelta(days=29)
    if hasta < desde:
        raise ErrorHttp(400, "hasta no puede ser anterior a desde")
    if (hasta - desde).days >= MAXIMO_DIAS:
        raise ErrorHttp(400, f"El periodo no puede superar {MAXIMO_DIAS} días")
    return desde, hasta


@manejar
def manejar_evento(evento, contexto):
    equipo_id = ruta(evento, "id")
    desde, hasta = _periodo(evento)
    resultado = db.ejecutar(
        "SELECT CAST(r.fecha_inicio AS text) AS inicio, CAST(r.fecha_fin AS text) AS fin "
        "FROM equipos e LEFT JOIN reservas r ON r.equipo_id = e.id "
        "AND r.estado IN ('pendiente', 'confirmada') "
        "AND daterange(r.fecha_inicio, r.fecha_fin, '[]') && "
        "daterange(CAST(:desde AS date), CAST(:hasta AS date), '[]') "
        "WHERE e.id = CAST(:id AS uuid) AND e.activo ORDER BY r.fecha_inicio",
        {"id": equipo_id, "desde": desde.isoformat(), "hasta": hasta.isoformat()},
    )
    if not resultado.filas:
        raise ErrorHttp(404, "El equipo no existe")

    ocupadas = [{"inicio": f["inicio"], "fin": f["fin"]} for f in resultado.filas if f["inicio"]]
    dias_ocupados = set()
    for tramo in ocupadas:
        dia = max(date.fromisoformat(tramo["inicio"]), desde)
        limite = min(date.fromisoformat(tramo["fin"]), hasta)
        while dia <= limite:
            dias_ocupados.add(dia)
            dia += timedelta(days=1)

    libres = []
    dia = desde
    while dia <= hasta:
        if dia not in dias_ocupados:
            libres.append(dia.isoformat())
        dia += timedelta(days=1)

    return respuesta(
        200,
        {"equipoId": equipo_id, "desde": desde.isoformat(), "hasta": hasta.isoformat(), "ocupadas": ocupadas, "libres": libres},
        {"Cache-Control": "no-store"},
    )
