variable "region" {
  type    = string
  default = "us-east-2"
}

variable "proyecto" {
  type    = string
  default = "terrafleet"
}

variable "entorno" {
  type    = string
  default = "dev"
}

variable "remitente_ses" {
  type = string
}

variable "correo_alarmas" {
  type    = string
  default = ""
}

variable "dominio" {
  type    = string
  default = ""
}

variable "zona_dns" {
  type    = string
  default = ""
}

variable "dispositivos" {
  type    = set(string)
  default = []
}

variable "umbral_sin_senal_segundos" {
  type    = number
  default = 120
}

variable "retencion_puntos_dias" {
  type    = number
  default = 30
}

variable "proteger_base_datos" {
  type    = bool
  default = false
}

variable "destruir_con_contenido" {
  type    = bool
  default = true
}
