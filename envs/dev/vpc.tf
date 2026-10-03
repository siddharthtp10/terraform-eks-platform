# -----------------------------------------------------------------------------
# Networking for the EKS cluster (Stage 3).
#
# Layout (2 AZs by default):
#   public subnets  -> route to an Internet Gateway; hold load balancers + NAT
#   private subnets -> route to the NAT gateway;     hold the worker nodes/pods
# Nodes sit in PRIVATE subnets so they have no public IPs and cannot be reached
# directly from the internet, but can still pull images and talk to AWS APIs
# outbound through the NAT.
# -----------------------------------------------------------------------------

# Ask AWS which AZs exist in this region instead of hard-coding "ap-south-1a".
# Hard-coded names break when moving regions, and some accounts don't have
# every AZ enabled. The filters drop Local Zones / Wavelength Zones, which
# aren't suitable for a normal EKS control-plane/subnet layout.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Take the first N AZ names. The list is sorted by AWS, so the result is
  # stable between runs (an unstable list would cause subnets to be replaced).
  azs = slice(data.aws_availability_zones.available.names, 0, var.azs_count)

  # --- cidrsubnet(prefix, newbits, netnum) ---------------------------------
  # Carves a smaller network out of a bigger one.
  #   newbits = how many extra bits to add to the prefix length
  #   netnum  = which of the resulting 2^newbits networks to pick (0-based)
  # With vpc_cidr = 10.0.0.0/16:
  #   cidrsubnet("10.0.0.0/16", 4, 0) -> 10.0.0.0/20   (16 + 4 = /20, 4096 IPs)
  #   cidrsubnet("10.0.0.0/16", 4, 1) -> 10.0.16.0/20  (each step skips 4096 IPs)
  #   cidrsubnet("10.0.0.0/16", 8, 240) -> 10.0.240.0/24 (16 + 8 = /24, 256 IPs)
  # Deriving ranges this way means changing vpc_cidr or azs_count can't leave
  # you with a typo'd or overlapping hand-written range.
  #
  # PRIVATE: /20 each (~4k IPs). Big on purpose: with the AWS VPC CNI every pod
  # gets a real VPC IP, so private subnets are what you run out of first.
  private_subnets = [for i in range(var.azs_count) : cidrsubnet(var.vpc_cidr, 4, i)]

  # PUBLIC: /24 each (~250 IPs). They only hold load balancer ENIs and the NAT
  # gateway, so small is fine. Starting at netnum 240 parks them at the top of
  # the VPC range (10.0.240.0/24, 10.0.241.0/24), far from the private /20s
  # (which occupy 10.0.0.0 onward), so the two blocks can never overlap.
  public_subnets = [for i in range(var.azs_count) : cidrsubnet(var.vpc_cidr, 8, 240 + i)]
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  # Exact pin (not "~>"). Unlike providers, modules have no lock file, so an
  # exact version is what makes builds reproducible. 6.7.3 was the latest
  # stable release when this was written; it needs AWS provider >= 6.28.
  version = "6.7.3"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # --- NAT gateway -----------------------------------------------------------
  # Private subnets have no route to the internet by themselves. A NAT gateway
  # (living in a public subnet) lets nodes START outbound connections (pull
  # images, call AWS APIs) while blocking unsolicited inbound traffic.
  enable_nat_gateway = true

  # COST vs RESILIENCE: single_nat_gateway = true builds ONE NAT gateway in one
  # AZ and routes every private subnet through it. A NAT gateway is billed per
  # hour whether or not it carries traffic PLUS per GB processed, so one instead
  # of one-per-AZ halves the fixed cost for 2 AZs. The trade-off: if that AZ
  # fails, private subnets in the OTHER AZ lose internet egress, and cross-AZ
  # traffic to reach the NAT is billed. Acceptable for a destroy-after-use demo.
  # FOR PRODUCTION: set single_nat_gateway = false and one_nat_gateway_per_az =
  # true, so each AZ has its own NAT and its own private route table.
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # --- DNS -------------------------------------------------------------------
  # EKS needs both. enable_dns_support makes the VPC's built-in resolver work;
  # enable_dns_hostnames gives instances DNS names. Nodes use them to resolve the
  # cluster's private API endpoint and AWS service endpoints (including the S3
  # and ECR names below), and the EKS control plane expects them on.
  enable_dns_support   = true
  enable_dns_hostnames = true

  # --- Subnet tags read by Kubernetes ----------------------------------------
  # The AWS cloud provider / AWS Load Balancer Controller scans the VPC for
  # subnets carrying these tags to decide where to place load balancers:
  #   kubernetes.io/role/elb          -> internet-facing LBs go in these subnets
  #   kubernetes.io/role/internal-elb -> internal LBs go in these subnets
  # Without them, creating a Service of type LoadBalancer / an Ingress fails
  # with "unable to find suitable subnets". The cluster tag marks the subnets as
  # usable by (shared with) this specific cluster.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  # --- Flow logs (OFF by default) --------------------------------------------
  # Flow logs record accepted/rejected connections per network interface: great
  # for debugging "why can't A reach B?" and for security forensics. But they
  # bill for CloudWatch Logs ingestion and storage, and a busy cluster generates
  # a lot. Turn on (enable_vpc_flow_logs = true) when investigating connectivity
  # or when a compliance rule requires network audit logs; keep retention short.
  enable_flow_log                                 = var.enable_vpc_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_vpc_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_vpc_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = 7
}

# --- S3 gateway endpoint -----------------------------------------------------
# A gateway endpoint adds a route in the private route table that sends S3
# traffic over AWS's private network instead of through the NAT gateway. It is
# FREE (no hourly or data charge), whereas every GB through the NAT is billed at
# the NAT data-processing rate. This matters because container image layers
# pulled from ECR are served from S3, and large pulls are typically the biggest
# source of NAT traffic in a cluster. It also keeps that traffic off the internet.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # With single_nat_gateway there is one private route table; with one NAT per
  # AZ there are several. The module output handles both.
  route_table_ids = module.vpc.private_route_table_ids

  tags = {
    Name = "${var.cluster_name}-s3"
  }
}
