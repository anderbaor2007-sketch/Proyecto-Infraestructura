output "subredes_ids" {
  value = aws_subnet.privadas[*].id
}

output "zonas" {
  value = local.zonas
}

output "grupo_seguridad_bd_id" {
  value = aws_security_group.base_datos.id
}
