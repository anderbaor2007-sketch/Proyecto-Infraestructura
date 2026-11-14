variable "nombre" {
  type = string
}

variable "funciones" {
  type = map(string)
}

variable "colas" {
  type = map(string)
}

variable "stream_nombre" {
  type = string
}

variable "api_nombre" {
  type = string
}

variable "etapa_api" {
  type = string
}

variable "correo_alarmas" {
  type    = string
  default = ""
}

variable "umbral_cola" {
  type    = number
  default = 100
}

variable "umbral_retraso_ms" {
  type    = number
  default = 60000
}

variable "destruir_con_contenido" {
  type    = bool
  default = true
}
