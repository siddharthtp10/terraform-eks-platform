output "state_bucket_name" {
  description = "Name of the state bucket. Copy into envs/dev/backend.hcl as `bucket`."
  value       = aws_s3_bucket.state.id
}

output "aws_region" {
  description = "Region of the state bucket. Copy into envs/dev/backend.hcl as `region`."
  value       = var.aws_region
}
