variable "name" {
  type        = string
  description = "Name of the queue (the dead-letter queue is named <name>-dlq)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,76}$", var.name))
    error_message = "Queue name must be 1-76 characters (room for the -dlq suffix): letters, numbers, underscores and hyphens."
  }
}

variable "max_receive_count" {
  type        = number
  description = "Receives (failed processing attempts) before a message moves to the dead-letter queue"
  default     = 3
  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}

variable "visibility_timeout_seconds" {
  type        = number
  description = "How long a received message stays hidden from other consumers; set it above the consumer's processing time"
  default     = 60
  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "message_retention_seconds" {
  type        = number
  description = "How long the main queue keeps a message (default 4 days)"
  default     = 345600
  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600."
  }
}

variable "dlq_retention_seconds" {
  type        = number
  description = "How long the dead-letter queue keeps a message (default and maximum 14 days, time to investigate)"
  default     = 1209600
  validation {
    condition     = var.dlq_retention_seconds >= 60 && var.dlq_retention_seconds <= 1209600
    error_message = "dlq_retention_seconds must be between 60 and 1209600."
  }
}
