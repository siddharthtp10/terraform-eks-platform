# -----------------------------------------------------------------------------
# GitHub Actions -> AWS without stored keys (OIDC federation).
#
# FLOW: each workflow job asks GitHub for a short-lived signed JWT that says who
# it is ("repo:OWNER/REPO:pull_request", ...). The job sends it to AWS STS
# (sts:AssumeRoleWithWebIdentity). AWS checks the signature against the identity
# provider below, then checks the role's TRUST POLICY conditions. If they match,
# STS returns temporary credentials (1 hour by default). Nothing long-lived ever
# exists in GitHub secrets, so there is nothing to leak or rotate.
#
# WHY THIS IS A SEPARATE CONFIG (ci-access/), applied by hand first: the pipeline
# cannot create the access it needs to run (chicken-and-egg, like bootstrap/).
# Having CI manage its own permissions would also let a bad PR grant itself more.
# -----------------------------------------------------------------------------

locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
  repo_full_name  = "${var.github_owner}/${var.github_repo}"
}

# One provider per URL per account. AWS now validates GitHub's certificate chain
# against its own trusted CA library, so no thumbprint needs to be configured.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = local.github_oidc_url
  client_id_list = ["sts.amazonaws.com"] # the audience the workflow requests
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = local.github_oidc_url
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# --- Trust policies ------------------------------------------------------------
# The `sub` (subject) claim is what stops OTHER repositories from using these
# roles. Without a sub condition, ANY GitHub repository on earth could assume the
# role, because every repo gets valid tokens from the same issuer. Always pin it.
#
# TWO roles, because plan and apply deserve different power and different gates:
#   plan  : read-only; assumable by pull_request runs of THIS repo.
#   apply : write; assumable ONLY by jobs that run in the protected GitHub
#           Environment (required reviewer + restricted to the main branch).
#           For those jobs GitHub puts "environment:<name>" in the sub claim.

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.repo_full_name}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only this repo, and only jobs bound to the approval-gated environment.
    # A job on a feature branch, a PR, or another environment gets a different
    # sub and is refused. (In GitHub, also restrict the environment to `main`.)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.repo_full_name}:environment:${var.apply_environment}"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.github_repo}-gha-plan"
  description          = "GitHub Actions: read-only terraform plan on pull requests (${local.repo_full_name})"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "apply" {
  name                 = "${var.github_repo}-gha-apply"
  description          = "GitHub Actions: terraform apply for envs/dev, approval-gated (${local.repo_full_name})"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "plan" {
  name   = "plan-read-only"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

resource "aws_iam_role_policy" "apply" {
  name   = "apply-envs-dev"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
