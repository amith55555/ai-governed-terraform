variable "name" {
  type        = string
  description = "Name of the Lambda function (the IAM role is named <name>-role)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,59}$", var.name))
    error_message = "Lambda function name must be 1-59 characters: letters, numbers, underscores and hyphens."
  }
}

variable "source_dir" {
  type        = string
  description = "Directory containing the Lambda function source code"
}

variable "table_name" {
  type        = string
  description = "Name of the DynamoDB table to be used by the Lambda function"
}

variable "table_arn" {
  type        = string
  description = "ARN of the DynamoDB table to be used by the Lambda function"
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket to be used by the Lambda function"
}

variable "bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket to be used by the Lambda function"
}

variable "memory_size" {
  type        = number
  description = "Amount of memory in MB allocated to the Lambda function"
  default     = 128
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
