variable "nombre" {
  type = string
}

variable "region" {
  type = string
}

variable "retencion_stream_horas" {
  type    = number
  default = 48
}

variable "dispositivos" {
  type    = set(string)
  default = []
}

variable "destruir_con_contenido" {
  type    = bool
  default = true
}
