output "dominio" {
  value = "${aws_api_gateway_rest_api.this.id}.execute-api.${data.aws_region.actual.name}.amazonaws.com"
}

output "etapa" {
  value = aws_api_gateway_stage.this.stage_name
}

output "nombre_api" {
  value = aws_api_gateway_rest_api.this.name
}
