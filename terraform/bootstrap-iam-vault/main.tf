provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  resolved_account_id = var.account_id != "" ? var.account_id : data.aws_caller_identity.current.account_id
  normalized_prefix   = trim(var.state_key_prefix, "/")
  object_prefix       = local.normalized_prefix != "" ? "${local.normalized_prefix}/" : ""
  terraform_role_arn  = "arn:aws:iam::${local.resolved_account_id}:role/${var.terraform_role_name}"
  terraform_instance_profile_arn = "arn:aws:iam::${local.resolved_account_id}:instance-profile/${var.terraform_role_name}"
  kms_key_arn_pattern            = "arn:aws:kms:${var.aws_region}:${local.resolved_account_id}:key/*"
  kms_alias_arn_pattern          = "arn:aws:kms:${var.aws_region}:${local.resolved_account_id}:alias/*"
}

resource "aws_iam_user" "vault" {
  name = var.vault_aws_user_name
  tags = var.tags
}

resource "aws_iam_role" "terraform" {
  name = var.terraform_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.vault.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "terraform_permissions" {
  name = "${var.terraform_role_name}-inline"
  role = aws_iam_role.terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = [local.terraform_role_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = [
          local.terraform_role_arn,
          local.terraform_instance_profile_arn
        ]
      },
      {
        Effect = "Allow"
        Action = ["iam:GetUser"]
        Resource = [aws_iam_user.vault.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:CreateKey",
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListResourceTags",
          "kms:EnableKeyRotation",
          "kms:PutKeyPolicy",
          "kms:ScheduleKeyDeletion",
          "kms:TagResource",
          "kms:UntagResource"
        ]
        Resource = [local.kms_key_arn_pattern]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:CreateAlias",
          "kms:UpdateAlias",
          "kms:DeleteAlias"
        ]
        Resource = [local.kms_alias_arn_pattern]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:ListAliases",
          "sts:GetCallerIdentity"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.state_bucket_name}"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = ["arn:aws:s3:::${var.state_bucket_name}/${local.object_prefix}*"]
      }
    ], var.additional_terraform_policy_statements)
  })
}

resource "aws_iam_user_policy" "vault_assume_role" {
  name = "${var.vault_aws_user_name}-assume-${var.terraform_role_name}"
  user = aws_iam_user.vault.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.terraform.arn
      }
    ]
  })
}

resource "aws_iam_access_key" "vault" {
  count = var.create_vault_access_key ? 1 : 0
  user  = aws_iam_user.vault.name
}
