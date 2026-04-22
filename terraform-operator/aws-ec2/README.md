
# AWS EC2 Terraform Operator

## Vault Configuration

### Create Vault Policy

```bash
vault policy write aws - <<EOF
path "secret/data/aws" {
    capabilities = ["read"]
}
EOF
```

### Write AWS Credentials Secret

KV v2 (path used by default in this chart):

```bash
vault kv put secret/aws ak=<AWS_ACCESS_KEY_ID> sk=<AWS_SECRET_ACCESS_KEY>
```

KV v1:

```bash
vault write secret/aws ak=<AWS_ACCESS_KEY_ID> sk=<AWS_SECRET_ACCESS_KEY>
```

### Create Kubernetes Auth Role

```bash
vault write auth/kubernetes/role/aws-ec2 \
         bound_service_account_names=aws-ec2 \
         bound_service_account_namespaces=default \
         policies=aws \
         audience=https://kubernetes.default.svc.cluster.local \
         ttl=24h
```

### Troubleshooting `permission denied` on `auth/token/create`

If Terraform fails with `failed to create limited child token` (HTTP 403 on
`/v1/auth/token/create`), configure the Vault provider with:

```hcl
provider "vault" {
    # ...
    skip_child_token = true
}
```

This avoids child token creation and uses the Kubernetes login token directly.

### Troubleshooting `no secret found at "secret/data/aws"`

1. Confirm the secret exists in Vault: `vault kv get secret/aws`.
2. Ensure chart values match that command:
    - `aws.vaultKvMount: secret`
    - `aws.vaultSecretName: aws`
3. Re-run Helm upgrade so runner pods get the updated TF vars.
4. If it still fails, verify you are reading from the same Vault namespace and server address used by the pod.
