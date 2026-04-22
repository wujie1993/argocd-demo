
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
