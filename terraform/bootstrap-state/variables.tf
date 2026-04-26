variable "aws_region" {
  description = "AWS region for the backend bucket."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for SSE-KMS. Leave empty to use SSE-S3 (AES256)."
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Allow bucket deletion when non-empty. Keep false in production."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
