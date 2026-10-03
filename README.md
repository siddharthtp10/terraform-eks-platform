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
- [x] 3. VPC
- [x] 4. EKS
- [ ] 5. GitHub Actions + OIDC + scanning
- [ ] 6. Flux GitOps
- [ ] 7. Final docs (architecture, cost, destroy, security)

## Cost

Everything except the state bucket is meant to be destroyed after each session.
The expensive item in the VPC stage is the **NAT gateway**, which bills for every
hour it exists (even with zero traffic) **plus** a charge per GB it processes.
The Elastic IP attached to it is also billed hourly as a public IPv4 address.
The VPC, subnets, route tables, internet gateway and the S3 gateway endpoint are free.

| Item (ap-south-1) | Price | Source |
|---|---|---|
| NAT gateway, per hour | _verify, see below_ | [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) |
| NAT gateway data processed, per GB | _verify, see below_ | [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) |
| Public IPv4 address (the NAT's EIP), per hour | _verify, see below_ | [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) (Public IPv4 Address tab) |

Prices are deliberately not hard-coded from memory: they change, and the figures
could not be confirmed from the AWS pricing page when this stage was written. Check them
yourself before relying on any estimate:

```bash
aws pricing get-products --region us-east-1 --service-code AmazonEC2 \
  --filters Type=TERM_MATCH,Field=regionCode,Value=ap-south-1 \
            Type=TERM_MATCH,Field=productFamily,Value="NAT Gateway" \
  --output json
```

### EKS (Stage 4)

| Item | Price | Source |
|---|---|---|
| EKS control plane, per cluster per hour (Kubernetes version in standard support) | **$0.10** | [Amazon EKS pricing](https://aws.amazon.com/eks/pricing/) |
| Same, if the version falls into extended support | $0.60 | [Amazon EKS pricing](https://aws.amazon.com/eks/pricing/) |
| 1 x `t3.medium` worker node (On-Demand, ap-south-1), per hour | _verify_ | [Amazon EC2 on-demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/) |
| EBS root volume of the node (20 GiB gp3 by default) | small; per GB-month | [Amazon EBS pricing](https://aws.amazon.com/ebs/pricing/) |
| KMS key for Secrets encryption | about $1 per month, prorated | [AWS KMS pricing](https://aws.amazon.com/kms/pricing/) |

The EKS control-plane price is the same in every region; it is the figure published
on the EKS pricing page ($0.10 standard, $0.60 extended). The node price
could not be confirmed from the AWS site when this stage was written, so look it up:

```bash
aws pricing get-products --region us-east-1 --service-code AmazonEC2 \
  --filters Type=TERM_MATCH,Field=regionCode,Value=ap-south-1 \
            Type=TERM_MATCH,Field=instanceType,Value=t3.medium \
            Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
            Type=TERM_MATCH,Field=tenancy,Value=Shared \
            Type=TERM_MATCH,Field=preInstalledSw,Value=NA \
            Type=TERM_MATCH,Field=capacitystatus,Value=Used \
  --output json
```

Estimated cost per hour = $0.10 (control plane) + node hourly rate + NAT hourly
rate + public IPv4 hourly rate (+ data processing). `terraform destroy` stops the clock.

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
