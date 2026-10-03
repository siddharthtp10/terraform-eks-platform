# -----------------------------------------------------------------------------
# EKS cluster (Stage 4) built with the community module.
#
# What the module creates for us: the EKS control plane, its IAM role, cluster
# and node security groups, a KMS key for Kubernetes Secrets encryption, the IAM
# OIDC provider (for IRSA), a managed node group + its IAM role, access
# entries, and the add-ons. Writing all that by hand is ~40 resources.
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

# -----------------------------------------------------------------------------
# SCANNER SUPPRESSIONS (Trivy): two ACCEPTED RISKS, reviewed and time-boxed.
# Both findings are located inside the community module, which is why the ignore
# comments sit on this module call. Each ignore names ONE rule and expires on the
# date shown, after which the scan fails again and forces a re-decision.
#
# AWS-0040 (CRITICAL) "Public cluster access is enabled": the API endpoint is
#   deliberately public so kubectl and `flux bootstrap` work from a laptop with no
#   VPN. It is NOT open to the internet: access is limited to var.api_allowed_cidrs
#   (validated to reject 0.0.0.0/0), and every call still needs IAM authentication
#   plus an EKS access entry. Trivy cannot see the CIDR restriction. Production
#   answer: a fully private endpoint reached over VPN/SSM.
#
# AWS-0104 (CRITICAL) "Security group rule allows unrestricted egress": this is the
#   module's default "egress_all" rule on the NODE security group. Nodes sit in
#   private subnets and must reach the internet through the NAT gateway to pull
#   images and call AWS APIs, and inbound traffic is still closed. Production
#   answer: restrict egress to VPC endpoints and known CIDRs, or add a proxy.
#
# SYNTAX WARNING: use ":exp:DATE" (colon). "exp=DATE" is silently ignored and would
# make the suppression permanent. Keep the ignore lines directly above `module`;
# a comment between them and the block disables the suppression.
# -----------------------------------------------------------------------------
#trivy:ignore:AVD-AWS-0040:exp:2027-03-31
#trivy:ignore:AVD-AWS-0104:exp:2027-03-31
module "eks" {
  source = "terraform-aws-modules/eks/aws"

  # Exact pin: modules have no lock file. 21.26.0 was the latest stable release
  # when written. v21 renamed many v20 inputs (name, kubernetes_version,
  # addons...), so never copy v20 examples blindly.
  version = "21.26.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # --- Networking (from Stage 3) ----------------------------------------------
  vpc_id = module.vpc.vpc_id

  # PRIVATE subnets only. Nodes get no public IPs and are unreachable from the
  # internet; they reach out through the NAT. The control plane's ENIs also land
  # here. Load balancers still go to the public subnets thanks to the Stage 3 tags.
  subnet_ids = module.vpc.private_subnets

  # --- API endpoint ------------------------------------------------------------
  # Private endpoint ON: nodes inside the VPC talk to the API over private IPs
  # (no NAT round trip, no dependency on the allow-list below).
  endpoint_private_access = true

  # Public endpoint ON but locked to YOUR IP, so kubectl and `flux bootstrap`
  # work from a laptop without a VPN.
  # TRADE-OFFS of a fully PRIVATE endpoint (public = false): the API is not on
  # the internet at all, which is the production-grade posture. But you can only
  # reach it from inside the VPC (VPN, Direct Connect, bastion/SSM, or a CI
  # runner in the VPC), so a laptop demo gets harder and GitHub-hosted runners
  # can't reach it. If you turn the PRIVATE endpoint off while keeping public
  # restricted, the nodes would reach the API via the NAT's IP and be blocked
  # unless that IP is allow-listed: keep both on, as here.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs

  # --- Authentication: access entries -------------------------------------------
  # "API" = only EKS access entries decide who can use the cluster. The legacy
  # aws-auth ConfigMap is ignored: no hand-edited YAML that can lock everyone
  # out, and access is managed through the AWS API (so Terraform/IAM/CloudTrail
  # all see it).
  authentication_mode = "API"

  # We do NOT use enable_cluster_creator_admin_permissions: it silently grants
  # admin to whoever ran `apply`, and would collide with the explicit entry
  # below when that is the same person. Explicit beats implicit.
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    admin = {
      principal_arn = var.admin_principal_arn

      policy_associations = {
        cluster_admin = {
          # AWS-managed access policy (not an account-specific ARN).
          policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster" # whole cluster; use "namespace" to scope down
          }
        }
      }
    }
  }

  # --- Control plane logging (OFF by default) ------------------------------------
  # Logs go to CloudWatch and bill for ingestion/storage, and `audit` is chatty.
  # Turn on when debugging authentication/authorisation ("who deleted that?"),
  # investigating a security event, or when compliance needs an audit trail.
  # Even then use a short retention.
  enabled_log_types                      = var.enable_control_plane_logs ? ["api", "audit", "authenticator", "controllerManager", "scheduler"] : []
  create_cloudwatch_log_group            = var.enable_control_plane_logs
  cloudwatch_log_group_retention_in_days = 7

  # --- IRSA ----------------------------------------------------------------------
  # Creates the cluster's IAM OIDC identity provider so pods can assume IAM roles
  # (worked example below, for the EBS CSI driver). True is the module default;
  # stated explicitly because the rest of this file depends on it.
  enable_irsa = true

  # --- Core add-ons managed by Terraform -------------------------------------------
  # Managing add-ons as EKS add-ons (not self-installed manifests) lets AWS
  # handle versions and compatibility. most_recent = true picks the newest
  # version compatible with this Kubernetes version at plan time: convenient,
  # but it means a plan can show an add-on upgrade later. For production, pin
  # addon_version per add-on and upgrade deliberately.
  addons = {
    # Pod networking: gives every pod a real VPC IP. before_compute = true so it
    # exists BEFORE the nodes join; otherwise nodes come up NotReady for lack of
    # a CNI.
    vpc-cni = {
      before_compute = true
    }

    # Service-side iptables/ipvs rules on each node. (Created after nodes.)
    kube-proxy = {}

    # Cluster DNS. Must come AFTER compute: its pods need a node to schedule on.
    coredns = {}

    # EBS CSI driver: lets pods use EBS volumes (PersistentVolumeClaims). Its
    # controller needs AWS permissions, supplied via the IRSA role below. The
    # add-on annotates its service account with this role ARN for us.
    aws-ebs-csi-driver = {
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }

  # --- Managed node group ------------------------------------------------------------
  # "Managed" = AWS provisions, patches and drains the nodes during updates.
  # One small node keeps the demo cheap; min 1 / max 2 gives a little headroom.
  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD" # Amazon Linux 2023, x86_64
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = 1
      max_size     = 2
      desired_size = 1

      # Explicit, though it inherits the cluster subnet_ids by default: nodes
      # must NEVER land in public subnets.
      subnet_ids = module.vpc.private_subnets
    }
  }
}

# -----------------------------------------------------------------------------
# IRSA worked example: IAM role for the EBS CSI controller's service account.
#
# HOW THE PIECES FIT TOGETHER
#  1. The cluster has an OIDC issuer URL; the IAM OIDC provider (created by the
#     module) tells AWS "trust identity tokens signed by this cluster".
#  2. Kubernetes gives each pod a signed service-account token (a JWT) whose
#     `sub` claim is "system:serviceaccount:<namespace>:<name>".
#  3. The service account carries the annotation
#     `eks.amazonaws.com/role-arn: <role>` (the add-on sets it for us). The AWS
#     SDK in the pod sees it and calls sts:AssumeRoleWithWebIdentity with the token.
#  4. THIS role's TRUST POLICY decides if that call succeeds: it only accepts
#     tokens from our OIDC provider whose `sub` is exactly that service account
#     and whose `aud` is sts.amazonaws.com. Other pods, namespaces and clusters are rejected.
#  5. STS returns short-lived credentials; no keys are stored anywhere.
# Without step 4's `sub` condition, any pod in the cluster could assume the role.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    # module.eks.oidc_provider = issuer URL without "https://", which is the
    # form IAM uses as the prefix of condition keys.
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name_prefix        = "${var.cluster_name}-ebs-csi-"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
}

# AWS-managed policy with exactly the EC2 volume/snapshot actions the driver needs.
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
