# terraform-eks-platform

A small, production-style Terraform platform on AWS: remote state, a VPC, an EKS
cluster, GitHub Actions CI/CD via OIDC, security scanning and Flux GitOps.
Designed to be cheap and **destroyed after use**.

> Status: **work in progress** - built stage by stage. Full docs land in Stage 7.

## Layout

| Path | Purpose |
|------|---------|
| `bootstrap/` | One-off config that creates the S3 state bucket (chicken-and-egg: state storage can't live in itself). |
| `envs/dev/` | The actual platform for the `dev` environment (VPC, EKS, ...). |
| `modules/` | Local reusable modules, only if community modules don't fit. |
| `.github/workflows/` | CI/CD pipelines (plan on PR, apply on merge). |
| `docs/` | Interview notes and design docs. |

## Stages

- [x] 1. Repo skeleton, `.gitignore`, pre-commit
- [x] 2. Remote state bootstrap
- [ ] 3. VPC
- [ ] 4. EKS
- [ ] 5. GitHub Actions + OIDC + scanning
- [ ] 6. Flux GitOps
- [ ] 7. Final docs (architecture, cost, destroy, security)

## Prerequisites (so far)

- Terraform >= 1.10 (needed for S3 native state locking)
- [pre-commit](https://pre-commit.com), [tflint](https://github.com/terraform-linters/tflint)

## Developer setup

```bash
pre-commit install      # run hooks automatically on commit
tflint --init           # download the AWS ruleset plugin
pre-commit run --all-files
```

## Safety

No credentials, account IDs or state files are ever committed. See `.gitignore`.
