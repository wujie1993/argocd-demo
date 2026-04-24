# AWS EC2 Terraform Operator

This chart runs a Terraform custom resource through terraform-operator to provision an EC2 instance and related IAM and KMS resources.

## What This Chart Creates

- An EC2 instance
- An IAM role and instance profile for the instance
- A customer-managed KMS key and alias for the root EBS volume

## Credential Modes

Set `aws.credentialsSource` to one of:

- `env`: read AWS credentials from a Kubernetes secret
- `vault-static`: read static AK/SK from Vault KV v2
- `vault-dynamic`: read short-lived AWS credentials from Vault AWS Secrets Engine

Mode-specific values:

- `env`: `aws.credsSecret`
- `vault-static`: `aws.vaultKvMount`, `aws.vaultKvSecretName`, `aws.vaultStaticAccessKeyField`, `aws.vaultStaticSecretKeyField`, `aws.vaultKubernetesAuthRole`
- `vault-dynamic`: `aws.vaultAwsBackend`, `aws.vaultAwsRole`, `aws.vaultAwsType`, `aws.vaultKubernetesAuthRole`

Recommended usage:

- `env`: simplest setup for local testing or short-lived demos; credentials live in Kubernetes
- `vault-static`: good when you already manage a fixed AWS IAM user's AK/SK in Vault
- `vault-dynamic` with `sts`: recommended for longer-term use; Vault issues short-lived credentials by assuming a target role
- `vault-dynamic` with `creds`: works, but usually requires broader IAM and KMS permissions than `sts`

Resolve your AWS account ID locally when needed:

```bash
aws sts get-caller-identity
```

## Common Prerequisites

Run once before using `vault-static` or `vault-dynamic`.

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://kubernetes.default.svc:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

Notes:

- Run this from a Vault pod so the token and CA paths exist
- The Vault pod service account must have permission to review Kubernetes tokens (`system:auth-delegator`)
- Replace `default` in auth role bindings below if your chart is deployed to another namespace

## Mode 1: Env (`env`)

Use this mode when you explicitly want Kubernetes to hold the AWS credentials.

Recommended setup:

- Use a dedicated IAM user for this chart
- Do not use root account access keys
- Store that IAM user's AK/SK in a Kubernetes secret referenced by `aws.credsSecret`

Create the Kubernetes secret:

```bash
kubectl create secret generic aws-creds \
    --from-literal=access-key=<AWS_ACCESS_KEY_ID> \
    --from-literal=secret-key=<AWS_SECRET_ACCESS_KEY>
```

Set chart values:

```yaml
aws:
  credentialsSource: env
  credsSecret: aws-creds
```

## Mode 2: Vault Static (`vault-static`)

Use this mode when you want Vault to store a fixed IAM user's access key and secret key.

Recommended setup:

- Create a dedicated IAM user for Terraform
- Do not use your personal IAM user
- Do not use the AWS account root
- Store that IAM user's AK/SK in Vault KV v2

1. Ensure KV v2 exists at `secret/`.

```bash
vault secrets enable -path=secret kv-v2
```

2. Write static credentials.

```bash
vault kv put secret/aws ak=<AWS_ACCESS_KEY_ID> sk=<AWS_SECRET_ACCESS_KEY>
```

3. Create a Vault policy for KV read.

```bash
vault policy write aws-static - <<EOF
path "secret/data/aws" {
    capabilities = ["read"]
}
EOF
```

4. Bind the Kubernetes auth role.

```bash
vault write auth/kubernetes/role/aws-ec2 \
    bound_service_account_names=aws-ec2 \
    bound_service_account_namespaces=default \
    policies=aws-static \
    audience=https://kubernetes.default.svc.cluster.local \
    ttl=24h
```

5. Set chart values.

```yaml
aws:
  credentialsSource: vault-static
  vaultKvMount: secret
  vaultKvSecretName: aws
  vaultStaticAccessKeyField: ak
  vaultStaticSecretKeyField: sk
  vaultKubernetesAuthRole: aws-ec2
```

## Mode 3: Vault Dynamic STS (`vault-dynamic` with `sts`)

This is the recommended long-term setup.

Vault uses a low-privilege source identity to assume a target IAM role. The target role holds the actual Terraform permissions.

### Recommended Model

1. Create a dedicated IAM user for Vault source credentials, for example `vault-aws-user`
2. Give that IAM user permission to call `sts:AssumeRole` on a target role, for example `terraform-aws-ec2`
3. Put the actual Terraform EC2/IAM/KMS permissions on the target role
4. Configure `aws/config/root` in Vault with the dedicated IAM user's AK/SK, not root account keys

Example names used below:

- Account ID: `<ACCOUNT_ID>`
- Vault source IAM user: `vault-aws-user`
- Terraform target role: `terraform-aws-ec2`

### Source IAM User Policy

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "arn:aws:iam::<ACCOUNT_ID>:role/terraform-aws-ec2"
        }
    ]
}
```

### Target Role Trust Policy

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::<ACCOUNT_ID>:user/vault-aws-user"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

### Target Role Permissions Policy

```json
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
                "iam:GetUser",
                "iam:ListRolePolicies",
                "iam:GetRolePolicy",
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
                "kms:GetKeyPolicy",
                "kms:GetKeyRotationStatus",
                "kms:ListAliases",
                "kms:ListResourceTags",
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
        }
    ]
}
```

### Example AWS CLI Flow

```bash
aws iam create-user --user-name vault-aws-user

aws iam put-user-policy \
    --user-name vault-aws-user \
    --policy-name vault-aws-assume-terraform-role \
    --policy-document file://vault-aws-user-policy.json

aws iam create-role \
    --role-name terraform-aws-ec2 \
    --assume-role-policy-document file://terraform-aws-ec2-trust-policy.json

aws iam put-role-policy \
    --role-name terraform-aws-ec2 \
    --policy-name terraform-aws-ec2-inline \
    --policy-document file://terraform-aws-ec2-policy.json

aws iam create-access-key --user-name vault-aws-user
```

### Configure Vault Root Credentials

Do not use root account access keys here.

```bash
vault secrets enable aws

vault write aws/config/root \
    access_key="<VAULT_AWS_USER_ACCESS_KEY>" \
    secret_key="<VAULT_AWS_USER_SECRET_KEY>" \
    region="us-east-1"
```

`region` here is for Vault AWS engine client defaults. It does not control Terraform deployment region.

### Create the Vault Dynamic STS Role

```bash
vault write aws/roles/aws-ec2 \
    credential_type="assumed_role" \
    role_arns="arn:aws:iam::<ACCOUNT_ID>:role/terraform-aws-ec2" \
    default_sts_ttl="1h" \
    max_sts_ttl="2h"
```

Requirements:

- The IAM identity in `aws/config/root` can call `sts:AssumeRole` on the target role
- The target role trust policy trusts that IAM user or IAM role
- The target role permissions allow the EC2/IAM/KMS actions required by this chart

### Create the Vault Runner Read Policy

```bash
vault policy write aws-ec2 - <<EOF
path "aws/sts/aws-ec2" {
    capabilities = ["read"]
}
EOF
```

If one policy should support both dynamic modes, include both paths:

```bash
vault policy write aws-ec2 - <<EOF
path "aws/creds/aws-ec2" {
    capabilities = ["read"]
}

path "aws/sts/aws-ec2" {
    capabilities = ["read"]
}
EOF
```

### Set Chart Values

```yaml
aws:
  credentialsSource: vault-dynamic
  vaultAwsBackend: aws
  vaultAwsRole: aws-ec2
  vaultAwsType: sts
```

## Mode 4: Vault Dynamic IAM User (`vault-dynamic` with `creds`)

Use this mode only if you specifically want Vault to mint IAM users instead of issuing STS credentials.

Compared with `sts`, this mode usually needs broader IAM and KMS permissions and Terraform will validate issued credentials with `iam:GetUser`.

### Configure Vault Root Credentials

```bash
vault secrets enable aws

vault write aws/config/root \
    access_key="<YOUR_VAULT_AWS_AK>" \
    secret_key="<YOUR_VAULT_AWS_SK>" \
    region="us-east-1"
```

Do not use root account access keys here. Use a dedicated IAM user or another non-root AWS identity for Vault's source credentials.

### Create the Vault Dynamic IAM User Role

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
                "iam:GetUser",
                "iam:ListRolePolicies",
                "iam:GetRolePolicy",
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
                "kms:GetKeyPolicy",
                "kms:GetKeyRotationStatus",
                "kms:ListAliases",
                "kms:ListResourceTags",
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
        }
    ]
}
EOF
```

Important notes:

- `vault_aws_access_credentials` validates `credential_type="iam_user"` credentials with `iam:GetUser`
- If `iam:GetUser` is missing, Terraform plan fails while reading Vault credentials
- If Terraform refreshes existing resources, the IAM and KMS read/list permissions above are also required
- The Terraform module configures the KMS key policy so EC2 and EBS can use the customer-managed key for the root volume in the current account and region

### Create the Vault Runner Read Policy

```bash
vault policy write aws-ec2 - <<EOF
path "aws/creds/aws-ec2" {
    capabilities = ["read"]
}
EOF
```

### Set Chart Values

```yaml
aws:
  credentialsSource: vault-dynamic
  vaultAwsBackend: aws
  vaultAwsRole: aws-ec2
  vaultAwsType: creds
```

## Bind Kubernetes Auth Role for Dynamic Modes

Use this when running either `vault-dynamic` mode.

```bash
vault write auth/kubernetes/role/aws-ec2 \
    bound_service_account_names=aws-ec2 \
    bound_service_account_namespaces=default \
    policies=aws-ec2 \
    audience=https://kubernetes.default.svc.cluster.local \
    ttl=24h
```

If one auth role should support both `vault-static` and `vault-dynamic`, use both policies:

```bash
vault write auth/kubernetes/role/aws-ec2 \
    bound_service_account_names=aws-ec2 \
    bound_service_account_namespaces=default \
    policies=aws-ec2,aws-static \
    audience=https://kubernetes.default.svc.cluster.local \
    ttl=24h
```

## Deploy

Example using chart defaults:

```bash
helm upgrade --install aws-ec2 . -n default
```

Use a custom values file per mode if needed:

```bash
helm upgrade --install aws-ec2 . -n default -f values.yaml
```

## Troubleshooting

### `permission denied` on `auth/token/create`

The Vault provider is configured with `skip_child_token = true`, so it reuses the login token instead of creating child tokens.

### `permission denied` on `auth/kubernetes/login`

1. Verify `auth/kubernetes/config` is set correctly
2. Verify the Vault service account has token review permission (`system:auth-delegator`)
3. Verify auth role name, namespace, service account, and audience values

### `permission denied` on `aws/creds/<role>` or `aws/sts/<role>`

1. Verify the Vault policy allows `read` on the required path
2. Verify the Kubernetes auth role includes that Vault policy
3. Verify chart values match backend, role, and type (`vaultAwsBackend`, `vaultAwsRole`, `vaultAwsType`)

### AWS Permission and KMS Errors

Use the failing AWS API action in Terraform output to identify where the run is blocked.

1. `iam:GetUser` while reading `data.vault_aws_access_credentials`
   This happens only in `vault-dynamic` with `aws.vaultAwsType=creds` (`credential_type="iam_user"`).
   The AWS provider skips its own credential validation, but the Vault data source still validates issued IAM-user credentials with `iam:GetUser`.
2. `iam:ListRolePolicies`, `iam:GetRolePolicy`, `kms:GetKeyPolicy`, `kms:GetKeyRotationStatus`, `kms:ListAliases`, or `kms:ListResourceTags` during plan or apply refresh
    Terraform refresh reads existing AWS resources before deciding changes.
3. `Client.InvalidKMSKey.InvalidState` while creating the EC2 instance
    The root EBS volume could not use the configured customer-managed KMS key.

For any AWS auth error, also confirm the runtime credentials allow:

1. `sts:GetCallerIdentity` for `data.aws_caller_identity.current`
2. The EC2/IAM/KMS actions required by this module

### `no secret found` in `vault-static` mode

1. Verify the secret exists: `vault kv get <mount>/<name>`
2. Verify values: `vaultKvMount`, `vaultKvSecretName`
3. Verify secret key names match: `vaultStaticAccessKeyField`, `vaultStaticSecretKeyField`
