variable "nombre" {
  type = string
}

variable "cognito_pool_arn" {
  type = string
}

variable "funciones" {
  type = map(object({
    nombre     = string
    invoke_arn = string
  }))
}

variable "etapa" {
  type    = string
  default = "prod"
}

variable "limite_tasa" {
  type    = number
  default = 100
}

variable "limite_rafaga" {
  type    = number
  default = 200
}
