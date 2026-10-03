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

# ----------------------------- Stage 4: EKS ----------------------------------

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. 1.36 was the newest version EKS supported when this was written (released on EKS 2 June 2026). Versions leave standard support after ~14 months; extended support costs extra per hour."
  type        = string
  default     = "1.36"
}

variable "admin_principal_arn" {
  description = "ARN of YOUR IAM user or role (the one you run kubectl as). It gets cluster-admin through an EKS access entry. No default on purpose: it contains your account ID, so supply it in the gitignored terraform.tfvars."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(user|role)/.+", var.admin_principal_arn))
    error_message = "admin_principal_arn must look like arn:aws:iam::<12-digit-account-id>:user/<name> or :role/<name>. For an SSO login use the role ARN without the /aws-reserved/... path (see `aws sts get-caller-identity` and the README)."
  }
}

variable "api_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the PUBLIC Kubernetes API endpoint, e.g. [\"203.0.113.10/32\"] (your IP). No default: forces a conscious choice."
  type        = list(string)

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && alltrue([for c in var.api_allowed_cidrs : can(cidrhost(c, 0))]) && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "Provide at least one valid CIDR and do not use 0.0.0.0/0 (that exposes the API to the whole internet)."
  }
}

variable "node_instance_types" {
  description = "Instance types for the managed node group. t3.medium is the smallest sensible size: t3.small caps at 11 pods (ENI/IP limits), which kube-system plus Flux in Stage 6 would exhaust."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND (predictable) or SPOT (cheaper, but AWS can reclaim the node with 2 minutes notice)."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "enable_control_plane_logs" {
  description = "Send EKS control plane logs (api, audit, authenticator, controllerManager, scheduler) to CloudWatch Logs. Off by default: ingestion + storage cost money."
  type        = bool
  default     = false
}
