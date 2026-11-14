CREATE INDEX IF NOT EXISTS idx_equipos_busqueda
    ON equipos (lower(ciudad), lower(categoria), lower(marca), tarifa_dia)
    WHERE activo
