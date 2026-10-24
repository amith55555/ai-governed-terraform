variable "name" {
  type        = string
  description = "Name of the DynamoDB table"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.name))
    error_message = "DynamoDB table name must be between 3 and 255 characters and can only contain letters, numbers, underscores, hyphens, and periods."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to enable deletion protection for the DynamoDB table"
  default     = true
}
