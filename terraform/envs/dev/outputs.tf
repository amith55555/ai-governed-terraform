output "api_endpoint" {
  description = "The endpoint of the HTTP API"
  value       = module.api.api_endpoint
  sensitive   = true
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

output "queue_url" {
  description = "URL of the SQS queue that receives new items"
  value       = module.queue.queue_url
}

output "dlq_name" {
  description = "Name of the SQS dead-letter queue for failed item messages"
  value       = module.queue.dlq_name
}
