variable "nombre" {
  type = string
}

variable "dominio_api" {
  type = string
}

variable "etapa_api" {
  type = string
}

variable "rutas_api" {
  type = list(string)
}

variable "contenido" {
  type = string
}

variable "configuracion" {
  type = map(string)
}

variable "alias" {
  type    = string
  default = ""
}

variable "certificado_arn" {
  type    = string
  default = ""
}

variable "limite_waf" {
  type    = number
  default = 2000
}

variable "destruir_con_contenido" {
  type    = bool
  default = true
}
