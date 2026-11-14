variable "nombre" {
  type = string
}

variable "url_base_inicial" {
  type    = string
  default = "https://pasarela.example.com/v1"
}

variable "dias_recuperacion" {
  type    = number
  default = 0
}
