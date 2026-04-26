# IaC-demo

## Fintech Hardening Tracker

Status key: [ ] not started, [~] in progress, [x] completed.

1. [ ] Remove long-lived IAM user key generation and secret outputs from bootstrap module.
2. [ ] Replace broad workload permissions (for example ec2:* on *) with least-privilege actions and resource scoping.
3. [ ] Enforce secure Vault transport (TLS) for provider connectivity.
4. [ ] Add explicit network controls (VPC, subnet, security group ingress/egress) for EC2 workload resources.
5. [ ] Define and document Terraform state controls for Kubernetes backend (encryption at rest, access boundaries, backup).
6. [ ] Expand CI policy scanning coverage to include bootstrap Terraform modules and Kubernetes/Helm manifests.
7. [ ] Align all runbooks/docs with the current architecture and remove stale bootstrap-state/S3 backend instructions.

Execution order for this repository: 7, 1, 2, 3, 4, 5, 6.

## Terraform Bootstrap Workspaces

This repository now includes two Terraform bootstrap workspaces to encapsulate AWS prerequisites:

- `terraform/bootstrap-state`: creates and hardens the S3 state bucket
- `terraform/bootstrap-iam-vault`: creates Vault source IAM user and Terraform target role

### Why split bootstrap from workload

- Solves the backend chicken-and-egg problem cleanly
- Keeps IAM and state infrastructure changes separate from workload changes
- Reduces manual setup steps in `terraform-operator/aws-ec2/README.md`

### Run Order

1. Apply `terraform/bootstrap-state`
2. Apply `terraform/bootstrap-iam-vault`
3. Configure Vault AWS Secrets Engine with outputs from step 2
4. Deploy the chart in `terraform-operator/aws-ec2`

### 1) Bootstrap State Bucket

```bash
cd terraform/bootstrap-state
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

### 2) Bootstrap IAM for Vault + Terraform

```bash
cd ../bootstrap-iam-vault
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Use `terraform output terraform_role_arn` from this workspace when creating Vault STS role configuration.

### 3) Wire the chart values to S3 backend

Set these values in `terraform-operator/aws-ec2/values.yaml` (or your override file):

```yaml
backend:
	type: s3
	s3:
		bucket: <STATE_BUCKET_NAME>
		key: workload/aws-ec2/terraform.tfstate
		region: <BUCKET_REGION>
		encrypt: true
		useLockfile: true
```

`useLockfile: true` uses native S3 lockfiles and does not require DynamoDB.

## GitHub Actions

This repository includes a Checkov workflow at `.github/workflows/checkov.yml`.

- It runs on pull requests when Terraform files under `terraform-operator` change.
- It scans the Terraform code with Checkov.
- The workflow fails on Checkov findings, which allows the PR check to block merges when branch protection requires it.