CREATE TABLE IF NOT EXISTS empresas (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre varchar(150) NOT NULL,
    ruc char(11) NOT NULL UNIQUE,
    correo varchar(200) NOT NULL,
    creado_en timestamptz NOT NULL DEFAULT now()
)
