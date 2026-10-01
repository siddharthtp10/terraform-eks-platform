# tflint configuration. Run `tflint --init` once to download the plugin below.

plugin "terraform" {
  enabled = true
  # "recommended" preset = naming conventions, unused declarations,
  # required_version/required_providers present, etc.
  preset = "recommended"
}

# AWS ruleset: checks provider-specific mistakes `terraform validate` cannot see
# (e.g. a non-existent instance type) without calling AWS.
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
