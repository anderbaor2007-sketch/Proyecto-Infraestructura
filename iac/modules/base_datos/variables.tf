variable "nombre" {
  type = string
}

variable "region" {
  type = string
}

variable "subredes_ids" {
  type = list(string)
}

variable "zonas" {
  type = list(string)
}

variable "grupo_seguridad_id" {
  type = string
}

variable "ruta_esquema" {
  type = string
}

variable "nombre_bd" {
  type    = string
  default = "terrafleet"
}

variable "version_motor" {
  type    = string
  default = "16.6"
}

variable "capacidad_min" {
  type    = number
  default = 0.5
}

variable "capacidad_max" {
  type    = number
  default = 4
}

variable "retencion_respaldo_dias" {
  type    = number
  default = 7
}

variable "proteger_borrado" {
  type    = bool
  default = false
}
