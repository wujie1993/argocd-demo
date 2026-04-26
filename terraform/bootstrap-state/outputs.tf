output "state_bucket_name" {
  description = "Terraform state bucket name."
  value       = aws_s3_bucket.tf_state.bucket
}

output "state_bucket_arn" {
  description = "Terraform state bucket ARN."
  value       = aws_s3_bucket.tf_state.arn
}

output "backend_region" {
  description = "Region used by the backend bucket."
  value       = var.aws_region
}
