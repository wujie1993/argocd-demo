# Bootstrap State

Creates the shared AWS backend resources used by Terraform state.

## What This Module Creates

- S3 bucket for Terraform state
- KMS key and alias for S3 backend encryption
- DynamoDB lock table for Terraform state locking (optional)
- S3 bucket hardening controls:
  - versioning enabled
  - public access blocked
  - bucket owner enforced
  - default SSE-KMS encryption
  - deny non-TLS access

## Why This Module Starts Local First

This module solves the backend chicken-and-egg problem.

The S3 backend resources do not exist yet on the first run, so the initial apply must use local state. After the bucket, KMS key, and optional lock table are created, you can migrate this module's own state into S3.

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Set `aws_region` and `state_bucket_name`.
3. Run the initial local apply:

```bash
terraform init
terraform apply
```

4. Copy `backend.hcl.example` to `backend.hcl`.
5. Replace `kms_key_id` in `backend.hcl` with the value from:

```bash
terraform output kms_key_arn
```

6. Migrate local state to S3:

```bash
terraform init -backend-config=backend.hcl -migrate-state
```

7. After confirming the backend is remote, remove leftover local state artifacts if present:

```bash
rm -f terraform.tfstate terraform.tfstate.backup
```

## Example Files

Example input values:

- `terraform.tfvars.example`
- `backend.hcl.example`

Keep the real `backend.hcl` uncommitted. The repository `.gitignore` already ignores `*.hcl`.

## Outputs

This module exposes:

- `state_bucket_name`
- `state_bucket_arn`
- `kms_key_arn`
- `lock_table_name`
- `backend_config_example`

You can reuse these values when configuring S3 backends for other Terraform workspaces.

## Notes

- One DynamoDB lock table is usually enough for many Terraform states in the same account and region.
- Use a unique backend `key` per stack or workspace.
- For stricter environments, explicitly set `kms_key_id` in backend config instead of relying only on bucket default encryption.
- `force_destroy` should normally stay `false` for production-like environments.
