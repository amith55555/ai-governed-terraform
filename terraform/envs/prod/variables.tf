variable "region" {
  type        = string
  description = "AWS region"
  default     = "eu-central-1"
}

variable "project" {
  type        = string
  description = "Project name, used in resource tags"
  default     = "ai-governed-terraform"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "AWS account ID must be 12 digits long."
  }
}

variable "alarm_email" {
  type        = string
  description = "Email address to receive CloudWatch alarm notifications"
  default     = null
}
