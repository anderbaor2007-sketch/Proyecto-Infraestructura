variable "nombre" {
  type = string
}

variable "remitente" {
  type = string
}

variable "visibilidad_segundos" {
  type    = number
  default = 180
}

variable "retencion_segundos" {
  type    = number
  default = 345600
}
