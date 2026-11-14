CREATE TABLE IF NOT EXISTS reservas (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    equipo_id uuid NOT NULL REFERENCES equipos (id),
    cliente_id varchar(64) NOT NULL,
    cliente_correo varchar(200) NOT NULL,
    fecha_inicio date NOT NULL,
    fecha_fin date NOT NULL,
    total numeric(12, 2) NOT NULL,
    estado varchar(20) NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'confirmada', 'rechazada', 'cancelada')),
    referencia_pago varchar(100),
    creado_en timestamptz NOT NULL DEFAULT now(),
    actualizado_en timestamptz NOT NULL DEFAULT now(),
    CHECK (fecha_fin >= fecha_inicio),
    EXCLUDE USING gist (
        equipo_id WITH =,
        daterange(fecha_inicio, fecha_fin, '[]') WITH &&
    ) WHERE (estado IN ('pendiente', 'confirmada'))
)
