output "account_id" {
  description = "Resolved AWS account ID used for generated ARNs."
  value       = local.resolved_account_id
}

output "vault_aws_user_arn" {
  description = "Vault source IAM user ARN."
  value       = aws_iam_user.vault.arn
}

output "terraform_role_arn" {
  description = "Target IAM role ARN to configure in Vault STS role."
  value       = aws_iam_role.terraform.arn
}

output "vault_write_aws_role_command" {
  description = "Command template to create Vault dynamic STS role."
  value       = "vault write aws/roles/aws-ec2 credential_type=assumed_role role_arns=${aws_iam_role.terraform.arn} default_sts_ttl=1h max_sts_ttl=2h"
}

output "vault_access_key_id" {
  description = "Vault IAM user access key ID when create_vault_access_key is true."
  value       = var.create_vault_access_key ? aws_iam_access_key.vault[0].id : null
}

output "vault_secret_access_key" {
  description = "Vault IAM user secret access key when create_vault_access_key is true."
  value       = var.create_vault_access_key ? aws_iam_access_key.vault[0].secret : null
  sensitive   = true
}
