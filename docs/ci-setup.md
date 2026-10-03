# CI/CD setup (GitHub Actions + OIDC)

One-time setup. Do these in order; the pipeline cannot bootstrap its own access.

## 1. Create the OIDC provider and roles (locally, once)

```bash
cd ci-access
cp terraform.tfvars.example terraform.tfvars   # set github_owner and state_bucket_name
cp backend.hcl.example backend.hcl             # same bucket as envs/dev, key ci-access/terraform.tfstate
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan                     # expect: 5 to add
terraform apply tfplan
terraform output                               # plan_role_arn, apply_role_arn
```

If your AWS account already has a GitHub OIDC provider, set `create_oidc_provider = false`
(an account can hold only one per URL).

## 2. GitHub repository settings

**Settings > Secrets and variables > Actions > Repository secrets**

| Secret | Value |
|---|---|
| `AWS_PLAN_ROLE_ARN` | `plan_role_arn` output |
| `TF_STATE_BUCKET` | your state bucket name |
| `ADMIN_PRINCIPAL_ARN` | the same value as `admin_principal_arn` in `envs/dev/terraform.tfvars` |
| `API_ALLOWED_CIDRS` | JSON list, e.g. `["203.0.113.10/32"]` |

**Same page > Variables tab > Repository variables** (not secret; one source of truth for every workflow):

| Variable | Value |
|---|---|
| `AWS_REGION` | the region of the platform and state bucket, e.g. `ap-south-1` |
| `TF_STATE_KEY` | the state key of `envs/dev`, `envs/dev/terraform.tfstate` unless you changed it. It must equal `state_key` in `ci-access` (its default is the same). |

The workflows stop with a clear error if either variable is missing. Also keep `cluster_name` identical in
`ci-access` and `envs/dev` (both default to `eks-dev`): the apply role's permissions are scoped to that name.

**Settings > Environments > New environment** named `dev-apply`:

- Required reviewers: add yourself. (Solo repo: leave "Prevent self-review" OFF.)
- Deployment branches: **Selected branches > main** only.
- Environment secret `AWS_APPLY_ROLE_ARN` = `apply_role_arn` output. Keeping it in the
  environment means PR workflows cannot even read it.

**Settings > Rules > Rulesets (or Branches) > protect `main`:**

- Require a pull request before merging.
- Require status checks: `fmt / validate / tflint / security scan` and `terraform plan (read-only)`.
- Block force pushes. Do not allow bypass (including admins).

**Settings > Actions > General:**

- Workflow permissions: **Read repository contents** (the workflows request more per job).
- Fork pull requests: require approval for all outside collaborators.
- Enable "Require actions to be pinned to a full-length commit SHA" if offered.

## 3. Test with a harmless PR

1. Branch, change one line in `README.md`, open a PR to `main`.
2. Expect: `fmt / validate / tflint / security scan` green, `terraform plan (read-only)`
   green, and one sticky "Terraform plan" comment with account IDs and IPs redacted.
   If the platform is currently destroyed the plan shows resources to create; if it is
   running it should say `No changes`.
3. Negative test (then close the PR without merging): add an ingress rule with
   `cidr_blocks = ["0.0.0.0/0"]` on port 22 to any `.tf` file. The security scan must fail
   the PR.

## 4. Deploying through CI

Actions > **Terraform Apply (envs/dev)** > Run workflow (branch `main`). The job pauses
for the `dev-apply` reviewer; approve it in the run page. Destroying is intentionally
NOT in CI: run `terraform destroy` locally (see the README).
