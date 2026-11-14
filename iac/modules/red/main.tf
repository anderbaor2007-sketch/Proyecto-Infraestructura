data "aws_availability_zones" "disponibles" {
  state = "available"
}

locals {
  zonas = slice(data.aws_availability_zones.disponibles.names, 0, 3)
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.nombre}-vpc"
  }
}

resource "aws_subnet" "privadas" {
  count             = length(local.zonas)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr, 8, count.index)
  availability_zone = local.zonas[count.index]

  tags = {
    Name = "${var.nombre}-privada-${count.index + 1}"
  }
}

resource "aws_security_group" "base_datos" {
  name        = "${var.nombre}-aurora"
  description = "Aurora PostgreSQL sin acceso de red directo; las funciones usan la Data API"
  vpc_id      = aws_vpc.this.id
}
