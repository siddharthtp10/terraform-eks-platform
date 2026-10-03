# -----------------------------------------------------------------------------
# bootstrap/  -  creates the S3 bucket that holds Terraform state for envs/dev.
#
# CHICKEN-AND-EGG: remote state needs a bucket, but a bucket needs Terraform,
# which needs somewhere to keep ITS state. We break the loop by applying this
# tiny config ONCE with local state (terraform.tfstate on your laptop, which is
# gitignored). Everything else then stores its state in the bucket created here.
#
# WHY THIS BUCKET MUST OUTLIVE THE PLATFORM: the platform (VPC, EKS, ...) is
# destroyed after every session to save money. `terraform destroy` needs the
# state to know what to delete, and the next `apply` needs history. If the state
# bucket lived inside the thing being destroyed it would delete its own memory
# mid-run. So it lives here, in a separate config that is NEVER destroyed
# (hence prevent_destroy below). An idle bucket holding a few KB costs pennies.
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  # default_tags are applied to every taggable resource automatically, so we
  # never forget tags and never repeat them per resource.
  default_tags {
    tags = {
      Project   = "terraform-eks-platform"
      Purpose   = "terraform-state"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # force_destroy = false: Terraform refuses to delete the bucket while it still
  # contains objects (state files!). Without it, one careless destroy could wipe
  # every state file.
  force_destroy = false

  # prevent_destroy is a second, Terraform-level seatbelt: any plan that would
  # destroy this resource errors out. To intentionally remove the bucket you must
  # edit this file first, which is exactly the deliberate friction we want.
  lifecycle {
    prevent_destroy = true
  }
}

# --- Versioning ---------------------------------------------------------------
# Every state write creates a new object version. If state is corrupted or a bad
# apply overwrites it, you can restore the previous version from the S3 console.
# This is your undo button for the most valuable file in the repo.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# --- Encryption at rest -------------------------------------------------------
# State routinely contains secrets in plaintext (DB passwords, generated keys),
# so it must be encrypted at rest.
#
# SSE-S3 (AES256) is used here: free, zero setup, no key to manage.
# bucket_key_enabled = true reduces per-request key overhead; it matters mostly
# for SSE-KMS but is harmless and future-proof here.
#
# WHEN I'D CHOOSE KMS (sse_algorithm = "aws:kms") INSTEAD:
#   - compliance requires a customer-managed key (rotation/ownership evidence),
#   - I need a CloudTrail record of every decrypt (who read the state?),
#   - I want access controlled by a key policy separate from bucket policy, or
#     the ability to cut off all access by disabling the key.
# COST: roughly $1/month per customer-managed key plus a small per-request
# charge (about $0.03 per 10,000 requests; check current AWS pricing). The
# bucket key above cuts KMS request volume by up to ~99%. Also remember every
# principal that reads state (including the CI role in Stage 5) then needs
# kms:Decrypt/GenerateDataKey on that key. For a demo, SSE-S3 is the right trade.
# Scanner suppression (Trivy AWS-0132 "use a customer managed key"): ACCEPTED RISK.
# SSE-S3 is a deliberate choice for this cost-conscious demo bucket (reasoning and
# the cost of KMS are in the comment above). Scoped to this one resource, with an
# expiry so the decision is revisited instead of forgotten. NOTE the syntax: Trivy
# only honours the expiry as ":exp:DATE" (colon). The "exp=DATE" form is silently
# ignored and makes the suppression permanent. The ignore line must sit directly
# above the resource, with no comment between them.
#trivy:ignore:AVD-AWS-0132:exp:2027-06-30
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# --- Block ALL public access --------------------------------------------------
# Four independent switches; turn all on. Even if someone later attaches a
# public ACL or policy by mistake, S3 ignores/rejects it. State must never be
# public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true # reject new public ACLs
  ignore_public_acls      = true # ignore any existing public ACLs
  block_public_policy     = true # reject bucket policies that grant public access
  restrict_public_buckets = true # limit access to AWS principals even if a policy is public
}

# --- Deny non-TLS requests ----------------------------------------------------
# Encryption at rest is not enough; state must not cross the network in
# cleartext either. aws:SecureTransport is false for plain HTTP, so we deny it.
data "aws_iam_policy_document" "deny_insecure_transport" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    # Both the bucket itself (ListBucket etc.) and the objects inside it.
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.deny_insecure_transport.json

  # S3 can reject a policy update that races with the public access block
  # settings ("OperationAborted: conflicting conditional operation"). An explicit
  # dependency serialises them. Terraform can't infer this: no attribute of the
  # block is referenced by the policy.
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# --- Lifecycle: stop paying for old state versions forever --------------------
# Versioning keeps every revision. 90 days of history is plenty for rollback,
# after which noncurrent versions are deleted. The current version is never
# touched by this rule.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    # Empty filter = apply to the whole bucket (required syntax in provider v6).
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Native locking creates and deletes a "<key>.tflock" object on every run.
    # On a versioned bucket each delete leaves a delete marker; this removes
    # markers once nothing is left behind them, so they don't accumulate.
    expiration {
      expired_object_delete_marker = true
    }

    # Clean up half-finished uploads, which are invisible but billed.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # The lifecycle API requires versioning to be on first for noncurrent rules.
  depends_on = [aws_s3_bucket_versioning.state]
}
