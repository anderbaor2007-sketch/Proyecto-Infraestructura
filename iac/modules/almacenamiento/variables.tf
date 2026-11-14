variable "nombre" {
  type = string
}

variable "origenes_permitidos" {
  type = list(string)
}

variable "destruir_con_contenido" {
  type    = bool
  default = true
}
