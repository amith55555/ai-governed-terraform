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
