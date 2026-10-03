terraform {
  # Must match bootstrap/. 1.10 introduced S3 native locking.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Same constraint as bootstrap/: >= 6.67.0, < 7.0.0 (6.67.0 was the latest
      # stable at time of writing). Exact version is frozen in
      # .terraform.lock.hcl, which is committed.
      version = "~> 6.67"
    }
  }
}
