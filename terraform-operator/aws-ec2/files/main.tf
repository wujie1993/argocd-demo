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
  # Kubernetes auth roles commonly do not allow auth/token/create.
  # Reuse the login token instead of requesting a child token.
  skip_child_token = true

  auth_login {
    path = "auth/kubernetes/login"

    parameters = {
      role = var.vault_kubernetes_auth_role
      jwt  = file("/var/run/secrets/kubernetes.io/serviceaccount/token")
    }
  }
}

data "vault_aws_access_credentials" "aws_creds" {
  count   = var.credentials_source == "vault-dynamic" ? 1 : 0
  backend = var.vault_aws_backend
  role    = var.vault_aws_role
  type    = var.vault_aws_type
}

data "vault_kv_secret_v2" "aws_static_creds" {
  count = var.credentials_source == "vault-static" ? 1 : 0
  mount = var.vault_kv_mount
  name  = var.vault_kv_secret_name
}

locals {
  # env            -> use AWS_* environment variables from Kubernetes secret
  # vault-static   -> read AK/SK from Vault KV v2
  # vault-dynamic  -> read short-lived AK/SK(+token) from Vault AWS Secrets Engine
  aws_access_key = (
    var.credentials_source == "vault-dynamic" ? data.vault_aws_access_credentials.aws_creds[0].access_key :
    var.credentials_source == "vault-static" ? data.vault_kv_secret_v2.aws_static_creds[0].data[var.vault_static_access_key_field] :
    null
  )
  aws_secret_key = (
    var.credentials_source == "vault-dynamic" ? data.vault_aws_access_credentials.aws_creds[0].secret_key :
    var.credentials_source == "vault-static" ? data.vault_kv_secret_v2.aws_static_creds[0].data[var.vault_static_secret_key_field] :
    null
  )
  aws_session_token = var.credentials_source == "vault-dynamic" ? try(data.vault_aws_access_credentials.aws_creds[0].security_token, null) : null
}

provider "aws" {
  region     = var.aws_region
  access_key = local.aws_access_key
  secret_key = local.aws_secret_key
  token      = local.aws_session_token
  # Vault dynamic credentials are typically scoped and may not include iam:GetUser.
  # Skip provider preflight credential validation to avoid requiring extra IAM permissions.
  skip_credentials_validation = true
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

variable "aws_region" {
  type = string
}

variable "ec2_name" {
  type = string
}

variable "ec2_instance_type" {
  type = string
}

variable "credentials_source" {
  type    = string
  default = "vault-dynamic"
  # "env"           - use AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars
  # "vault-static"  - read AWS AK/SK from Vault KV v2 secret
  # "vault-dynamic" - read dynamic AWS creds from Vault AWS Secrets Engine

  validation {
    condition     = contains(["env", "vault-static", "vault-dynamic"], var.credentials_source)
    error_message = "credentials_source must be one of: env, vault-static, vault-dynamic."
  }
}

variable "vault_kv_mount" {
  type    = string
  default = "secret"
}

variable "vault_kv_secret_name" {
  type    = string
  default = "aws"
}

variable "vault_static_access_key_field" {
  type    = string
  default = "ak"
}

variable "vault_static_secret_key_field" {
  type    = string
  default = "sk"
}

variable "vault_aws_backend" {
  type    = string
  default = "aws"
}

variable "vault_aws_role" {
  type    = string
  default = "aws-ec2"
}

variable "vault_aws_type" {
  type    = string
  default = "creds"
}

variable "vault_kubernetes_auth_role" {
  type    = string
  default = "aws-ec2"
}