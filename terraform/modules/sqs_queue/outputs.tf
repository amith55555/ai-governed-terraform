output "queue_url" {
  description = "URL of the queue"
  value       = aws_sqs_queue.this.id
}

output "queue_arn" {
  description = "ARN of the queue"
  value       = aws_sqs_queue.this.arn
}

output "queue_name" {
  description = "Name of the queue"
  value       = aws_sqs_queue.this.name
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the dead-letter queue"
  value       = aws_sqs_queue.dlq.name
}
