# Bootstrap IAM for Vault

Creates AWS IAM resources used by Vault AWS Secrets Engine and Terraform workloads.

## What This Module Creates

- IAM user for Vault source credentials (`vault_aws_user_name`)
- IAM role assumed by Vault-issued credentials (`terraform_role_name`)
- Inline policy on that role for EC2/IAM/KMS/S3 state operations
- Optional IAM access key for the Vault IAM user

## Vault Prerequisites

Complete these before using dynamic credentials from Vault:

1. Enable Kubernetes auth in Vault.
2. Configure Kubernetes auth with token reviewer JWT and cluster CA.
3. Enable AWS secrets engine in Vault.
4. Configure aws/config/root in Vault using a dedicated non-root IAM user.
5. Create a Vault AWS role (recommended: assumed_role / STS).
6. Create a Vault policy that allows reading credentials from that role path.
7. Bind a Vault Kubernetes auth role to the service account and namespace used by the chart.

Suggested Vault auth paths and role names can be aligned with values used in terraform-operator/aws-ec2.

### Default Commands (vault-dynamic with sts)

Use this as the default path because the chart defaults to `vaultAwsType: sts`.

```bash
vault write auth/kubernetes/config \
	token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
	kubernetes_host="https://kubernetes.default.svc:443" \
	kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

```bash
vault write aws/roles/aws-ec2 \
	credential_type="assumed_role" \
	role_arns="arn:aws:iam::<ACCOUNT_ID>:role/terraform-workload-role" \
	default_sts_ttl="1h" \
	max_sts_ttl="2h"
```

```bash
vault policy write aws-ec2 - <<EOF
path "aws/sts/aws-ec2" {
	capabilities = ["read"]
}
EOF
```

```bash
vault write auth/kubernetes/role/aws-ec2 \
	bound_service_account_names=aws-ec2 \
	bound_service_account_namespaces=default \
	policies=aws-ec2 \
	audience=https://kubernetes.default.svc.cluster.local \
	ttl=24h
```

### Alternative Commands (vault-dynamic with iam_user)

The following matches a working flow for `aws-ec2`:

```bash
vault write auth/kubernetes/config \
	token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
	kubernetes_host="https://kubernetes.default.svc:443" \
	kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

```bash
vault write aws/roles/aws-ec2 \
	credential_type="iam_user" \
	ttl="1h" \
	policy_document=-<<EOF
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Action": [
				"ec2:*",
				"iam:CreateRole",
				"iam:DeleteRole",
				"iam:GetRole",
				"iam:TagRole",
				"iam:UntagRole",
				"iam:PassRole",
				"iam:AttachRolePolicy",
				"iam:DetachRolePolicy",
				"iam:ListAttachedRolePolicies",
				"iam:CreateInstanceProfile",
				"iam:DeleteInstanceProfile",
				"iam:GetInstanceProfile",
				"iam:AddRoleToInstanceProfile",
				"iam:RemoveRoleFromInstanceProfile",
				"iam:ListInstanceProfilesForRole",
				"kms:CreateKey",
				"kms:DescribeKey",
				"kms:EnableKeyRotation",
				"kms:PutKeyPolicy",
				"kms:ScheduleKeyDeletion",
				"kms:CreateAlias",
				"kms:UpdateAlias",
				"kms:DeleteAlias",
				"kms:TagResource",
				"kms:UntagResource",
				"sts:GetCallerIdentity"
			],
			"Resource": "*"
		},
		{
			"Effect": "Allow",
			"Action": [
				"s3:ListBucket"
			],
			"Resource": "arn:aws:s3:::<STATE_BUCKET_NAME>"
		},
		{
			"Effect": "Allow",
			"Action": [
				"s3:GetObject",
				"s3:PutObject",
				"s3:DeleteObject"
			],
			"Resource": "arn:aws:s3:::<STATE_BUCKET_NAME>/<STATE_KEY_PREFIX>*"
		}
	]
}
EOF
```

```bash
vault policy write aws-ec2 - <<EOF
path "aws/creds/aws-ec2" {
	capabilities = ["read"]
}
EOF
```

```bash
vault write auth/kubernetes/role/aws-ec2 \
	bound_service_account_names=aws-ec2 \
	bound_service_account_namespaces=default \
	policies=aws-ec2 \
	audience=https://kubernetes.default.svc.cluster.local \
	ttl=24h
```

Use `vaultAwsType: creds` when using this `iam_user` mode.
For production, prefer `vaultAwsType: sts` with a tightly scoped assumed role.

### EC2 Permissions for the Bootstrap Role

This module's default inline policy includes IAM/KMS/S3. Add EC2 permissions with `additional_terraform_policy_statements` in `terraform.tfvars`.

```hcl
additional_terraform_policy_statements = [
	{
		Effect = "Allow"
		Action = [
			"ec2:*"
		]
		Resource = ["*"]
  	}		
]
```

## Terraform Usage

1. Copy terraform.tfvars.example to terraform.tfvars.
2. Set aws_region, state_bucket_name, and names for vault_aws_user_name and terraform_role_name.
3. Optionally add permissions through additional_terraform_policy_statements.
4. Run terraform init, terraform plan, and terraform apply.

## Security Notes

- Prefer Vault dynamic STS credentials over static AK/SK.
- Avoid AWS root access keys.
- Keep additional policy statements least-privilege and resource-scoped.
