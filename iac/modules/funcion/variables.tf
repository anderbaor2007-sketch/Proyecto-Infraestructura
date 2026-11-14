variable "nombre" {
  type = string
}

variable "codigo" {
  type = string
}

variable "manejador" {
  type    = string
  default = "handler.manejar_evento"
}

variable "memoria" {
  type    = number
  default = 256
}

variable "tiempo" {
  type    = number
  default = 10
}

variable "variables" {
  type    = map(string)
  default = {}
}

variable "capas" {
  type    = list(string)
  default = []
}

variable "retencion_logs" {
  type    = number
  default = 30
}

variable "permisos" {
  type = list(object({
    acciones = list(string)
    recursos = list(string)
    condiciones = optional(list(object({
      test     = string
      variable = string
      valores  = list(string)
    })), [])
  }))
  default = []
}
