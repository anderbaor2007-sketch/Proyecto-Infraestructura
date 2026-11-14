CREATE TABLE IF NOT EXISTS equipos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id uuid NOT NULL REFERENCES empresas (id),
    nombre varchar(150) NOT NULL,
    categoria varchar(60) NOT NULL,
    marca varchar(60) NOT NULL,
    modelo varchar(80),
    ciudad varchar(80) NOT NULL,
    tarifa_dia numeric(10, 2) NOT NULL CHECK (tarifa_dia > 0),
    descripcion text,
    foto_clave varchar(300),
    activo boolean NOT NULL DEFAULT true,
    creado_en timestamptz NOT NULL DEFAULT now()
)
