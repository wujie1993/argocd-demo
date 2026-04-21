# argocd-demo

## GitHub Actions

This repository includes a Checkov workflow at `.github/workflows/checkov.yml`.

- It runs on pull requests when Terraform files under `terraform-operator` change.
- It scans the Terraform code with Checkov.
- The workflow fails on Checkov findings, which allows the PR check to block merges when branch protection requires it.