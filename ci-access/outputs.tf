# Paste these into GitHub (Settings > Secrets and variables > Actions). They contain
# your account ID, so treat them as secrets: never commit them or put them in the
# workflow YAML.

output "plan_role_arn" {
  description = "Repository secret AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Environment secret AWS_APPLY_ROLE_ARN (add it to the apply environment, not the repo)."
  value       = aws_iam_role.apply.arn
}
