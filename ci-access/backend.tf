# Same PARTIAL backend pattern as envs/dev (see the explanation there), but with
# its OWN state key so a mistake here can't corrupt the platform's state:
#   terraform init -backend-config=backend.hcl     (key = "ci-access/terraform.tfstate")
terraform {
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
