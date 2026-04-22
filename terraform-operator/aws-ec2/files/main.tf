terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.2"
}

provider "vault" {
  address = "http://vault.vault.svc.cluster.local:8200"

  auth_login {
    path = "auth/kubernetes/login"

    parameters = {
      role = "aws-ec2"
      jwt  = local.vault_kubernetes_jwt
    }
  }
}

locals {
  vault_kubernetes_jwt = var.vault_kubernetes_jwt != "" ? var.vault_kubernetes_jwt : try(trimspace(file("/var/run/secrets/kubernetes.io/serviceaccount/token")), "")
}

# 2. 从 KV-V2 引擎读取 AWS 凭证
data "vault_generic_secret" "aws_creds" {
  path = "secret/data/aws" # KV-V2 引擎需要在路径中加上 "data"
}

provider "aws" {
  region = var.aws_region
  access_key = data.vault_generic_secret.aws_creds.data["ak"]
  secret_key = data.vault_generic_secret.aws_creds.data["sk"]
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_iam_role" "app_server" {
  name               = "${var.ec2_name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.ec2_name}-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.app_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_server" {
  name = "${var.ec2_name}-instance-profile"
  role = aws_iam_role.app_server.name
}

#checkov:skip=CKV_AWS_109: KMS key policies require an account administration statement for key management.
#checkov:skip=CKV_AWS_111: The administration statement is intentionally scoped to the current account root principal.
#checkov:skip=CKV_AWS_356: AWS KMS key policies use Resource "*" because the policy is attached directly to the key.
resource "aws_kms_key" "ebs" {
  description         = "KMS key for ${var.ec2_name} EC2 root volume encryption"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.ec2_name}-ebs"
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.ec2_name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

resource "aws_instance" "app_server" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.ec2_instance_type
  ebs_optimized        = true
  monitoring           = true
  iam_instance_profile = aws_iam_instance_profile.app_server.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted  = true
    kms_key_id = aws_kms_key.ebs.arn
  }

  tags = {
    Name = var.ec2_name
  }
}

# 变量（Helm 注入）
variable "aws_region" {
  type = string
}

variable "ec2_name" {
  type = string
}

variable "ec2_instance_type" {
  type = string
}

variable "vault_kubernetes_jwt" {
  type      = string
  sensitive = true
  default   = ""
}