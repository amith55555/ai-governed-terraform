variable "name" {
  type        = string
  description = "Name of the S3 bucket"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.name)) && length(var.name) >= 3 && length(var.name) <= 63
    error_message = "S3 bucket name must be 3–63 characters, lowercase letters, digits, hyphens, starting and ending with a letter or digit."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Delete all objects when destroying the bucket. Use true only in non-production environments."
  default     = false
}

variable "cloudfront_distribution_arn" {
  type        = string
  description = "ARN of a CloudFront distribution allowed to read objects (through OAC). null means no CloudFront access."
  default     = null
}

variable "cloudfront_read_prefix" {
  type        = string
  description = "Key prefix CloudFront may read, for example \"items/\". Must end with \"/\"."
  default     = "items/"
  validation {
    condition     = can(regex("^[a-zA-Z0-9!_.'()-]+(/[a-zA-Z0-9!_.'()-]+)*/$", var.cloudfront_read_prefix))
    error_message = "cloudfront_read_prefix must be a non-empty key prefix ending with \"/\" (no wildcards)."
  }
}
