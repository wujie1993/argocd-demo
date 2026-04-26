output "state_bucket_name" {
  description = "S3 bucket name for Terraform state."
  value       = aws_s3_bucket.tf_state.bucket
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for Terraform state."
  value       = aws_s3_bucket.tf_state.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for S3 state encryption."
  value       = aws_kms_key.tf_state.arn
}

output "lock_table_name" {
  description = "DynamoDB lock table name if created."
  value       = var.create_lock_table ? aws_dynamodb_table.tf_state_locks[0].name : null
}

output "backend_config_example" {
  description = "Example backend.hcl settings for other Terraform workspaces."
  value = {
    bucket         = aws_s3_bucket.tf_state.bucket
    key            = "REPLACE-ME/terraform.tfstate"
    region         = var.aws_region
    encrypt        = true
    kms_key_id     = aws_kms_key.tf_state.arn
    dynamodb_table = var.create_lock_table ? aws_dynamodb_table.tf_state_locks[0].name : null
  }
}
