provider "aws" {
  region = var.aws_region

  # Credentials are intentionally NOT configured here. The provider picks them up
  # from the standard chain (env vars, AWS_PROFILE/SSO locally, or the OIDC role
  # in CI). Nothing secret ever appears in code.

  # default_tags stamps every taggable resource: useful for cost allocation
  # ("show me everything tagged Project=terraform-eks-platform") and for finding
  # leftovers after a destroy.
  default_tags {
    tags = {
      Project     = "terraform-eks-platform"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
