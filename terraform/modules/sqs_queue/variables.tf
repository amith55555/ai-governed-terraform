variable "name" {
  type        = string
  description = "Name of the queue (the dead-letter queue is named <name>-dlq)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,76}$", var.name))
    error_message = "Queue name must be 1-76 characters (80 with the -dlq suffix): letters, numbers, underscores and hyphens."
  }
}

variable "max_receive_count" {
  type        = number
  description = "Number of failed receives after which a message moves to the dead-letter queue"
  default     = 3
  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000 && floor(var.max_receive_count) == var.max_receive_count
    error_message = "max_receive_count must be a whole number from 1 to 1000."
  }
}

variable "message_retention_seconds" {
  type        = number
  description = "How long the main queue keeps a message, in seconds (60 to 1209600)"
  default     = 345600 # 4 days, the SQS default
  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be from 60 to 1209600 (14 days)."
  }
}

variable "visibility_timeout_seconds" {
  type        = number
  description = "How long a received message stays hidden from other consumers, in seconds (0 to 43200)"
  default     = 30
  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be from 0 to 43200 (12 hours)."
  }
}
