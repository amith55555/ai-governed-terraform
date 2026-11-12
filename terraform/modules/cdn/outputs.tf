output "distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Domain name of the CloudFront distribution (the frontend loads files from https://<domain_name>/items/...)"
  value       = aws_cloudfront_distribution.this.domain_name
}
