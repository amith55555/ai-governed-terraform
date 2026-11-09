variable "name_prefix" {
  type        = string
  description = "Prefix for the names of the resources created by this module"
}

variable "function_name" {
  type        = string
  description = "Name of the Lambda function"
}

variable "api_id" {
  type        = string
  description = "ID of the HTTP API to which the Lambda function will be attached"
}

variable "alarm_email" {
  type        = string
  description = "Email address to receive alarm notifications"
  default     = null
}

variable "function_timeout_seconds" {
  type        = number
  description = "Timeout of the Lambda function in seconds; the duration alarm fires above 80% of it"

  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 900
    error_message = "function_timeout_seconds must be between 1 and 900 (the Lambda limit)."
  }
}
