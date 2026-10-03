# Consumed by Stage 4 (EKS) via direct references, and handy for `terraform output`.

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (one per AZ). Worker nodes go here."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ). Load balancers and the NAT gateway live here."
  value       = module.vpc.public_subnets
}
