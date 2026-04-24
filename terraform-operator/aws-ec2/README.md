
# AWS EC2 Terraform Operator

This chart runs a Terraform CR through terraform-operator to provision an EC2 instance and related IAM/KMS resources.

## Credential Modes

Set `aws.credentialsSource` to one of:

- `env`: read AWS credentials from a Kubernetes secret
- `vault-static`: read static credentials from Vault KV v2
- `vault-dynamic`: read short-lived credentials from Vault AWS Secrets Engine

Mode-specific values:

- `env`: `aws.credsSecret`
- `vault-static`: `aws.vaultKvMount`, `aws.vaultKvSecretName`, `aws.vaultStaticAccessKeyField`, `aws.vaultStaticSecretKeyField`, `aws.vaultKubernetesAuthRole`
- `vault-dynamic`: `aws.vaultAwsBackend`, `aws.vaultAwsRole`, `aws.vaultAwsType`, `aws.vaultKubernetesAuthRole`

## Common Prerequisites (Vault + Kubernetes Auth)

Run once before using `vault-static` or `vault-dynamic`.

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://kubernetes.default.svc:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

Notes:

- Run this from a Vault pod so token/CA paths exist.
- The Vault pod service account must have permission to review Kubernetes tokens (`system:auth-delegator`).
- Replace `default` in auth role bindings below if your chart is deployed to another namespace.

## Vault Static Mode Setup (`vault-static`)

1. Ensure KV v2 mount exists (skip if already enabled at `secret/`).

```bash
vault secrets enable -path=secret kv-v2
```

2. Write static credentials.

```bash
vault kv put secret/aws ak=<AWS_ACCESS_KEY_ID> sk=<AWS_SECRET_ACCESS_KEY>
```

3. Create Vault policy for KV read.

```bash
vault policy write aws-static - <<EOF
path "secret/data/aws" {
    capabilities = ["read"]
}
EOF
```

4. Bind Kubernetes auth role.

```bash
vault write auth/kubernetes/role/aws-ec2 \
    bound_service_account_names=aws-ec2 \
    bound_service_account_namespaces=default \
    policies=aws-static \
    audience=https://kubernetes.default.svc.cluster.local \
    ttl=24h
```

## Vault Dynamic Mode Setup (`vault-dynamic`)

`vault-dynamic` supports two patterns:

- `aws.vaultAwsType: creds` with `credential_type="iam_user"`
- `aws.vaultAwsType: sts` with `credential_type="assumed_role"`

### 1. Enable AWS secrets engine and set root config

```bash
vault secrets enable aws

vault write aws/config/root \
    access_key="<YOUR_VAULT_AWS_AK>" \
    secret_key="<YOUR_VAULT_AWS_SK>" \
    region="us-east-1"
```

`region` here is for Vault AWS engine client defaults. It does not control Terraform deployment region.

### 2A. `iam_user` mode (`aws.vaultAwsType: creds`)

Create dynamic role:

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

Important: when `aws.vaultAwsType` is `creds` (`credential_type="iam_user"`), Terraform's `vault_aws_access_credentials` data source validates newly issued credentials by calling `iam:GetUser`. If this action is missing, plan fails while reading Vault creds.

This policy can be tightened for production, but missing IAM/KMS actions will cause Terraform apply failures for this chart.

If Terraform is managing existing resources (or refreshing prior state), include the read/list permissions above as well. Without them, plan can fail during refresh with errors such as `iam:ListRolePolicies`, `kms:GetKeyPolicy`, or `kms:ListAliases`.

The Terraform module also configures the KMS key policy so EC2/EBS can use the customer-managed key for the instance root volume in the current account and region.

Create runner read policy for `creds` path:

```bash
vault policy write aws-ec2 - <<EOF
path "aws/creds/aws-ec2" {
    capabilities = ["read"]
}
EOF
```

### 2B. `assumed_role` mode (`aws.vaultAwsType: sts`)

Create dynamic role:

```bash
vault write aws/roles/aws-ec2 \
    credential_type="assumed_role" \
    role_arns="arn:aws:iam::<ACCOUNT_ID>:role/<TERRAFORM_TARGET_ROLE>" \
    default_sts_ttl="1h" \
    max_sts_ttl="2h"
```

Requirements for assumed role:

- The IAM identity in `aws/config/root` can call `sts:AssumeRole` on `<TERRAFORM_TARGET_ROLE>`.
- Target role trust policy trusts that root identity.
- Target role permissions allow required EC2/IAM/KMS actions for this chart.

Create runner read policy for `sts` path:

```bash
vault policy write aws-ec2 - <<EOF
path "aws/sts/aws-ec2" {
    capabilities = ["read"]
}
EOF
```

If you want one policy to support both dynamic modes, include both paths:

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

### 3. Bind Kubernetes auth role for dynamic mode

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

## Env Mode Setup (`env`)

Create the Kubernetes secret referenced by `aws.credsSecret`:

```bash
kubectl create secret generic aws-creds \
    --from-literal=access-key=<AWS_ACCESS_KEY_ID> \
    --from-literal=secret-key=<AWS_SECRET_ACCESS_KEY>
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

1. Verify `auth/kubernetes/config` is set correctly.
2. Verify Vault service account has token review permission (`system:auth-delegator`).
3. Verify auth role name, namespace, service account, and audience values.

### `permission denied` on `aws/creds/<role>`

1. Verify Vault policy allows `read` on `aws/creds/<role>`.
2. Verify Kubernetes auth role includes that policy.
3. Verify chart values match backend/role (`vaultAwsBackend`, `vaultAwsRole`, `vaultAwsType`).

### AWS permission and KMS errors

Use the failing API action in the Terraform output to identify which stage is blocked.

1. `iam:GetUser` while reading `data.vault_aws_access_credentials`
    This happens only in `vault-dynamic` with `aws.vaultAwsType=creds` (`credential_type="iam_user"`).
    The AWS provider is configured with `skip_credentials_validation = true`, but the Vault data source still validates issued IAM-user credentials with `iam:GetUser`.
    Ensure the Vault AWS role policy includes `iam:GetUser`.
2. `iam:ListRolePolicies`, `iam:GetRolePolicy`, `kms:GetKeyPolicy`, `kms:GetKeyRotationStatus`, `kms:ListAliases`, or `kms:ListResourceTags` during plan/apply refresh
    Terraform refresh reads existing AWS resources before deciding changes.
    Ensure the Vault-issued credentials include the IAM and KMS read/list actions documented in the `iam_user` policy example above.
3. `Client.InvalidKMSKey.InvalidState` while creating the EC2 instance
    The root EBS volume could not use the configured customer-managed KMS key.
    Verify the KMS key is enabled, not pending deletion, and that the key policy allows EC2/EBS use in the current account and region.

For any AWS auth error, also confirm the runtime credentials still allow:

1. `sts:GetCallerIdentity` for `data.aws_caller_identity.current`
2. The EC2/IAM/KMS actions required by this module

### `no secret found` in `vault-static` mode

1. Verify secret exists: `vault kv get <mount>/<name>`.
2. Verify values: `vaultKvMount`, `vaultKvSecretName`.
3. Verify secret key names match: `vaultStaticAccessKeyField`, `vaultStaticSecretKeyField`.
