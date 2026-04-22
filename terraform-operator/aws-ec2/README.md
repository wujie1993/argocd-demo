
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
