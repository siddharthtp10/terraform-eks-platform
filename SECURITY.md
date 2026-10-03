# Security policy

This is a portfolio and learning project: a small Terraform platform on AWS (S3 remote state,
VPC, EKS, GitHub Actions with OIDC, Flux GitOps) that is meant to be created for a short
session and destroyed afterwards. There is no production deployment and no real user data.

## Reporting a vulnerability

Please report security problems **privately** through GitHub:
**Security tab > Report a vulnerability** (private vulnerability reporting).
Do not open a public issue for anything sensitive.

Useful reports include:

- a secret, token, account ID or private key that appears in the repository or its history;
- an IAM, trust-policy or workflow weakness (for example a way for another repository or a
  pull request to assume the CI roles, or to exfiltrate secrets);
- a Terraform or Kubernetes default that is insecure and not already listed below.

You will get an acknowledgement; this is a personal project, so response times are best effort.

## Known and accepted risks

Some scanner findings are deliberate demo trade-offs. Each is suppressed in code with a written
justification and an expiry date (search for `trivy:ignore`) and listed in the README under
"Accepted scanner findings". Reports about those are welcome only if you can show they are worse
than described there.

## What is intentionally not in this repository

No AWS credentials, account IDs, ARNs, state files, `terraform.tfvars`, `backend.hcl`,
kubeconfigs or tokens are committed. CI uses short-lived OIDC credentials, and the Flux
bootstrap token is only ever read from an environment variable at run time.
