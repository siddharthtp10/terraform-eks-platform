terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67" # same constraint as the rest of the repo; exact version in the lock file
    }
  }
}
