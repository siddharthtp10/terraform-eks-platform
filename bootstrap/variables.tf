variable "aws_region" {
  description = "AWS region for the state bucket. Keep it identical to the region used by envs/dev."
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally unique name for the Terraform state bucket. S3 bucket names share
    one namespace across ALL AWS accounts, so there is deliberately no default.
    Tip: include something personal/random, e.g. "tfstate-<yourname>-<random>".
  EOT
  type        = string

  # Fail at `plan` time with a clear message instead of failing halfway through
  # `apply` with an opaque S3 API error.
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "Bucket name must be 3-63 chars: lowercase letters, numbers, dots and hyphens, starting and ending with a letter or number."
  }
}
