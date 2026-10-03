variable "aws_region" {
  description = "Region the platform (and the state bucket) live in."
  type        = string
  default     = "ap-south-1"
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository, exactly as it appears in the URL (the claim is case-sensitive)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name. The roles trust ONLY this repository."
  type        = string
  default     = "terraform-eks-platform"
}

variable "apply_environment" {
  description = "Name of the GitHub Environment that gates apply (must have required reviewers). The apply role can only be assumed by jobs running in this environment."
  type        = string
  default     = "dev-apply"
}

variable "state_bucket_name" {
  description = "Name of the state bucket from bootstrap/. Used to scope the roles' S3 permissions to the state objects only."
  type        = string
}

variable "state_key" {
  description = "State object key used by envs/dev (the `key` in its backend.hcl)."
  type        = string
  default     = "envs/dev/terraform.tfstate"
}

variable "cluster_name" {
  description = "EKS cluster name used by envs/dev. IAM, EKS, KMS and log permissions are scoped to names derived from it, so it must match."
  type        = string
  default     = "eks-dev"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. An AWS account can hold only ONE provider per URL: set false if it already exists (the config then looks it up)."
  type        = bool
  default     = true
}
