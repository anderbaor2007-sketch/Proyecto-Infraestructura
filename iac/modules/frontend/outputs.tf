output "dominio" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "zona_id" {
  value = aws_cloudfront_distribution.this.hosted_zone_id
}

output "distribucion_id" {
  value = aws_cloudfront_distribution.this.id
}

output "bucket" {
  value = aws_s3_bucket.frontend.bucket
}
