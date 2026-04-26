# AWS EC2 Terraform Operator

Helm chart to run Terraform via terraform-operator for a simple EC2 workload.

The Terraform custom resource used by this chart is powered by GalleyBytes terraform-operator:
https://github.com/GalleyBytes/terraform-operator

## Fintech Hardening Checklist

Status key: [ ] not started, [~] in progress, [x] completed.

1. [ ] Use Vault dynamic STS only for this chart path and phase out env/vault-static options where possible.
2. [ ] Enforce Vault TLS endpoint usage for provider communication.
3. [ ] Add explicit EC2 networking controls (subnet and security groups with restricted ingress/egress).
4. [ ] Document Kubernetes backend state controls and operational safeguards.
5. [ ] Keep chart docs consistent with active backend and bootstrap flow.

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

## Install

```bash
helm upgrade --install aws-ec2 ./terraform-operator/aws-ec2 -f values.yaml
```

## Notes

- Prefer least privilege IAM policies.
- Prefer Vault dynamic STS over long-lived static keys.
- If you add new AWS resources, extend IAM permissions through `additional_terraform_policy_statements` in `terraform/bootstrap-iam-vault/terraform.tfvars`.
