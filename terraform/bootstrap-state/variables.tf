variable "aws_region" {
  description = "AWS region for the backend resources."
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state."
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB lock table."
  type        = string
  default     = "terraform-state-locks"
}

variable "create_lock_table" {
  description = "Whether to create a DynamoDB table for Terraform state locking."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Whether to allow Terraform to delete the state bucket even if it contains objects."
  type        = bool
  default     = false
}

variable "kms_key_deletion_window_in_days" {
  description = "Deletion window for the backend KMS key."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all created resources."
  type        = map(string)
  default     = {}
}
