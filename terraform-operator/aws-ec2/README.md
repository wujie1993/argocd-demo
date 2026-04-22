
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

```bash
vault kv put secret/aws ak=<AWS_ACCESS_KEY_ID> sk=<AWS_SECRET_ACCESS_KEY>
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

## Troubleshooting

### `permission denied` on `auth/token/create`

The Vault Kubernetes auth role does not permit child token creation. The Vault provider is configured with `skip_child_token = true` to reuse the login token directly.

### `no secret found`

1. Confirm the secret exists: `vault kv get secret/aws`.
2. Check `aws.vaultKvMount` and `aws.vaultSecretName` in values match the engine mount and key name.
3. Run `helm upgrade` so runner pods receive the updated `TF_VAR_*` environment variables.
