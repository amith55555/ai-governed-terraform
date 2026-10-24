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
