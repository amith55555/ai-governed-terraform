output "queue_url" {
  description = "URL of the queue"
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN of the queue"
  value       = aws_sqs_queue.this.arn
}

output "dead_letter_queue_arn" {
  description = "ARN of the dead-letter queue"
  value       = aws_sqs_queue.dead_letter.arn
}
