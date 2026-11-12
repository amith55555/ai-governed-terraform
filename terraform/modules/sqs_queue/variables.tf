variable "name" {
  type        = string
  description = "Name of the queue; the dead-letter queue is named <name>-dlq"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,76}$", var.name))
    error_message = "Queue name must be 1-76 characters: letters, numbers, underscores and hyphens."
  }
}

variable "max_receive_count" {
  type        = number
  description = "Receives before a message moves to the dead-letter queue"
  default     = 3
  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}

variable "visibility_timeout_seconds" {
  type        = number
  description = "How long a received message is hidden from other consumers"
  default     = 30
}

variable "alarm_topic_arn" {
  type        = string
  description = "ARN of the SNS topic that the dead-letter alarm notifies"
}
