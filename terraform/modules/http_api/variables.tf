variable "name" {
  type        = string
  description = "Name of the HTTP API"
}

variable "lambda_function_name" {
  type        = string
  description = "Name of the Lambda function to be used as the integration for the HTTP API"
}

variable "lambda_invoke_arn" {
  type        = string
  description = "ARN of the Lambda function to be used as the integration for the HTTP API"
}

variable "throttle_rate_limit" {
  type        = number
  description = "The maximum number of requests per second for the HTTP API"
  default     = 10
  validation {
    condition     = var.throttle_rate_limit > 0
    error_message = "throttle_rate_limit must be a positive number."
  }
}

variable "throttle_burst_limit" {
  type        = number
  description = "Maximum number of requests the API accepts in a short spike, above the steady rate limit"
  default     = 20
  validation {
    condition     = var.throttle_burst_limit > 0
    error_message = "throttle_burst_limit must be a positive number."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain logs in CloudWatch"
  default     = 14
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90], var.log_retention_days)
    error_message = "log_retention_days must be one of: 1, 3, 5, 7, 14, 30, 60, 90."
  }
}
