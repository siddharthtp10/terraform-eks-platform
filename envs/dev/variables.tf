variable "aws_region" {
  description = "AWS region for the dev platform. Must match the region you intend to deploy into (and normally the state bucket's region)."
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Subnet ranges are derived from it with cidrsubnet(), so it must be /16 or larger (smaller prefix number)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix length of /16 or shorter (for example 10.0.0.0/16)."
  }
}

variable "azs_count" {
  description = "How many Availability Zones to spread subnets across. EKS requires subnets in at least 2 AZs."
  type        = number
  default     = 2

  validation {
    condition     = var.azs_count >= 2 && var.azs_count <= 6
    error_message = "azs_count must be between 2 (EKS minimum) and 6."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster created in Stage 4. Needed NOW because the subnets must carry kubernetes.io/cluster/<name> tags so Kubernetes can discover them."
  type        = string
  default     = "eks-dev"
}

variable "single_nat_gateway" {
  description = "true = ONE shared NAT gateway (cheap, single AZ point of failure). false = one NAT gateway per AZ (resilient, costs N times more)."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs. Off by default because it costs money for ingestion and storage; see vpc.tf."
  type        = bool
  default     = false
}
