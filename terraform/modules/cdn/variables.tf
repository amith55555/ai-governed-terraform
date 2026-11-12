variable "name" {
  type        = string
  description = "Name of the distribution and its origin access control"
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket served by the distribution"
}

variable "bucket_regional_domain_name" {
  type        = string
  description = "Regional domain name of the S3 bucket (bucket.s3.region.amazonaws.com)"
}

variable "price_class" {
  type        = string
  description = "CloudFront price class (edge locations used)"
  default     = "PriceClass_100"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}
