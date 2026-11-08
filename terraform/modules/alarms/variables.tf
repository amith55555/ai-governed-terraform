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

variable "lambda_duration_threshold_ms" {
  type        = number
  description = "Lambda Maximum Duration alarm threshold in milliseconds; set to about 80% of the Lambda timeout"
  default     = 8000

  validation {
    condition     = var.lambda_duration_threshold_ms > 0 && var.lambda_duration_threshold_ms <= 900000
    error_message = "lambda_duration_threshold_ms must be greater than 0 and at most 900000 (15 minutes)."
  }
}
