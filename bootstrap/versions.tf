terraform {
  # >= 1.10 is the first release with S3 native state locking
  # (`use_lockfile = true`). Using it means no DynamoDB lock table to build,
  # pay for, or secure. This bootstrap itself uses LOCAL state, but we keep the
  # same floor so the whole repo is developed with one Terraform generation.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # "~> 6.67" means >= 6.67.0 and < 7.0.0: we accept bug-fix/minor releases
      # but never an automatic major bump (majors contain breaking changes).
      # 6.67.0 was the latest stable release when this was written. The exact
      # version actually used is frozen by .terraform.lock.hcl (commit it!).
      version = "~> 6.67"
    }
  }
}
