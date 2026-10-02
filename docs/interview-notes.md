# Interview notes

Plain-language Q&A per stage. Read the answers out loud until they sound natural.

## Stage 1 - Repo skeleton, .gitignore, pre-commit

**Q1. Why split into `bootstrap/` and `envs/dev/` instead of one folder?**
Terraform needs somewhere to store state, but the bucket for state must itself be
created by something. `bootstrap/` creates the bucket using local state once;
`envs/dev/` then uses that bucket as its remote backend. Separate folders also
mean separate state files, so a mistake in the platform can't touch the bucket.

**Q2. What must never be committed to git, and why?**
`*.tfstate` (contains resource details and often secrets in plaintext),
`*.tfvars` (environment-specific values), `.terraform/` (downloaded plugins,
huge and reproducible) and kubeconfigs (cluster credentials).

**Q3. Should `.terraform.lock.hcl` be committed?**
Yes. It records exact provider versions and checksums, so CI and every laptop
download identical plugins. Ignoring it is a common mistake.

**Q4. What do `fmt`, `validate` and `tflint` each catch?**
`fmt` = style only. `validate` = syntax and internal consistency (a reference to
an undeclared variable). `tflint` = deeper lint and provider-aware rules (unused
variables, invalid instance types, missing version constraints). None of them
talk to AWS or prove the plan will succeed; only `plan` does.

**Q5. How does this differ from your CloudFormation workflow?**
CloudFormation stores state for you inside the service (the stack). Terraform
makes *you* own state: where it lives, who can read it, how it is locked. In
return you get one tool across clouds, a real `plan` diff before every change,
and a module/registry ecosystem. The repo structure is also my choice rather
than "one template per stack".

### Commonly breaks at this stage
`terraform_validate` fails in pre-commit with *"Module not installed"* or
*"Missing required provider"* because nothing has been `init`-ed yet.
Debug: run `terraform init -backend=false` in the failing directory, then re-run
`pre-commit run --all-files`; read the hook output, which names the directory.

## Stage 2 - Remote state bootstrap

**Q1. Why use remote state instead of the default local `terraform.tfstate`?**
State is Terraform's record of what it built. On a laptop it is a single copy
that one person owns: lose the laptop and Terraform forgets your infrastructure;
a teammate (or the CI pipeline) can't run it at all. Remote state in S3 is shared,
backed up, encrypted and access-controlled, which is the prerequisite for CI/CD.

**Q2. What does state locking prevent?**
Two runs writing state at the same time. Without a lock, two `apply`s each read
the same starting state, make different changes, and the last writer silently
overwrites the first, leaving real resources that Terraform no longer knows about
(orphans) or thinks exist when they don't. With locking the second run fails fast
with "Error acquiring the state lock" and shows who holds it.

**Q3. S3 native locking vs a DynamoDB lock table?**
Before Terraform 1.10 the S3 backend needed a separate DynamoDB table for locks.
Now `use_lockfile = true` makes Terraform write a `<key>.tflock` object next to
the state using an S3 conditional write ("create only if it doesn't exist"), so
only one writer can succeed. Fewer resources, no extra table to pay for or give
IAM permissions on. (The DynamoDB method is deprecated.) The CI role later needs
S3 permission on that `.tflock` object too, not just on the state file.

**Q4. Why turn on versioning and encryption for the state bucket?**
Versioning is the undo button: if state is corrupted or a bad run overwrites it,
restore the previous version. Encryption (plus blocking public access and denying
non-TLS requests) matters because state routinely contains secrets such as
passwords and keys in plaintext, so it is one of the most sensitive files you own.

**Q5. What happens if the bootstrap's own local state is lost?**
The bucket and the platform state inside it are untouched; only Terraform's
bookkeeping for the *bucket* is gone. Recovery is to re-run bootstrap with the
same variables and `terraform import` the existing bucket and its sub-resources
(versioning, encryption, public access block, policy, lifecycle) so Terraform
adopts them rather than trying to create duplicates. That is why this config is
tiny, why the bucket has `prevent_destroy`, and why the bucket name is recorded
somewhere safe. A common alternative is to migrate bootstrap's state into the
bucket afterwards; the trade-off is a slightly circular dependency.

### Commonly breaks at this stage
`apply` fails with `BucketAlreadyExists` (the name is taken by someone else) or
`BucketAlreadyOwnedByYou` (you made it earlier), or init fails with `Invalid
security token` / region errors.
Debug: `aws sts get-caller-identity` (confirm which account/identity you are),
check `aws_region` in tfvars equals `region` in backend.hcl, and pick a more
unique bucket name. Re-run `terraform plan`; S3 names are global, not per-account.
