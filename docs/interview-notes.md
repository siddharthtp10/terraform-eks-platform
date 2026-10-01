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
