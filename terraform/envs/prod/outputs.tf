output "api_endpoint" {
  description = "The endpoint of the HTTP API"
  value       = module.api.api_endpoint
}

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = module.table.table_name
}

output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.bucket.bucket_name
}

output "function_name" {
  description = "Name of the Lambda function"
  value       = module.lambda.function_name
}
