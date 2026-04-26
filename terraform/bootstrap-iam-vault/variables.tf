variable "aws_region" {
  description = "AWS region for provider operations."
  type        = string
}

variable "account_id" {
  description = "Optional AWS account ID override. Empty means auto-detect."
  type        = string
  default     = ""
}

variable "vault_aws_user_name" {
  description = "IAM user used by Vault AWS Secrets Engine root config."
  type        = string
  default     = "vault-aws-user"
}

variable "terraform_role_name" {
  description = "IAM role assumed by Vault-issued STS credentials for Terraform runs."
  type        = string
  default     = "terraform-workload-role"
}

variable "state_bucket_name" {
  description = "S3 bucket name used for Terraform state backend."
  type        = string
}

variable "state_key_prefix" {
  description = "State key prefix for this workload, for example aws-ec2/."
  type        = string
  default     = "aws-ec2/"
}

variable "create_vault_access_key" {
  description = "If true, create an access key for the Vault IAM user and expose it as sensitive output."
  type        = bool
  default     = false
}

variable "additional_terraform_policy_statements" {
  description = "Additional IAM policy statements appended to the module's default least-privilege policy."
  type        = list(any)
  default     = []
}

variable "tags" {
  description = "Tags to apply to created IAM resources."
  type        = map(string)
  default     = {}
}
