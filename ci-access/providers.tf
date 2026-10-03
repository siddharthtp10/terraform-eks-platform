provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "terraform-eks-platform"
      Purpose   = "ci-access"
      ManagedBy = "terraform"
    }
  }
}
