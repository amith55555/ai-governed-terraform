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

variable "github_repository" {
  type        = string
  description = "GitHub repository path in the format 'owner/repo'"
  default     = "amith55555/ai-governed-terraform"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "GitHub repository must be in the format 'owner/repo'."
  }
}

variable "github_owner_id" {
  type        = string
  description = "GitHub owner ID (numeric)"
  default     = "97042431"
  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "GitHub owner ID must be a numeric string."
  }
}

variable "github_repository_id" {
  type        = string
  description = "GitHub repository ID (numeric)"
  default     = "1431221190"
  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "GitHub repository ID must be a numeric string."
  }
}
