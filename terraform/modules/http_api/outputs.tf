output "api_endpoint" {
  description = "The endpoint of the HTTP API"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_id" {
  description = "The ID of the HTTP API"
  value       = aws_apigatewayv2_api.this.id
}
