# AWS EC2 Terraform Operator

Helm chart to run Terraform via terraform-operator for a simple EC2 workload.

## What It Provisions

- EC2 instance
- IAM role and instance profile for the instance
- KMS key and alias for root EBS encryption

## Prerequisites

- Kubernetes cluster with terraform-operator installed
- AWS account and permissions for this workload
- Terraform state bucket already created (for example from `terraform/bootstrap-state`)

## Credential Sources

Set `aws.credentialsSource` to one of:

- `env`: read AK/SK from a Kubernetes secret
- `vault-static`: read static AK/SK from Vault KV v2
- `vault-dynamic`: read short-lived credentials from Vault AWS secrets engine

Recommended default: `vault-dynamic` with `vaultAwsType: sts`.

## Minimal Values

### Env mode

```yaml
aws:
  credentialsSource: env
  credsSecret: aws-creds
```

Create secret:

```bash
kubectl create secret generic aws-creds \
  --from-literal=access-key=<AWS_ACCESS_KEY_ID> \
  --from-literal=secret-key=<AWS_SECRET_ACCESS_KEY>
```

### Vault static mode

```yaml
aws:
  credentialsSource: vault-static
  vaultKvMount: secret
  vaultKvSecretName: aws
  vaultStaticAccessKeyField: ak
  vaultStaticSecretKeyField: sk
  vaultKubernetesAuthRole: aws-ec2
```

### Vault dynamic mode (STS)

```yaml
aws:
  credentialsSource: vault-dynamic
  vaultAwsBackend: aws
  vaultAwsRole: aws-ec2
  vaultAwsType: sts
  vaultKubernetesAuthRole: aws-ec2
```

## Known Limitations

- The current GalleyBytes `terraform-operator` task image family in use does not yet provide Terraform `>= 1.10` tags.
- Because of that, native S3 lockfiles (`use_lockfile = true`) cannot be enabled yet for this chart.
- Until the operator runtime version problem is resolved, use the current backend approach and treat native lockfile support as deferred work.

## Install

```bash
helm upgrade --install aws-ec2 ./terraform-operator/aws-ec2 -f values.yaml
```

## Notes

- Prefer least privilege IAM policies.
- Prefer Vault dynamic STS over long-lived static keys.
- If you add new AWS resources, extend IAM permissions through `additional_terraform_policy_statements` in `terraform/bootstrap-iam-vault/terraform.tfvars`.
