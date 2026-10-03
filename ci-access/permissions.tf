# -----------------------------------------------------------------------------
# Permissions for the two CI roles.
#
# Honest summary: these are SCOPED, not perfect. They were derived from the
# resources envs/dev actually creates (VPC, EKS, KMS, IAM roles) and tightened
# by resource name, region and conditions wherever AWS allows it. The first real
# CI apply may reveal a missing action: read the AccessDenied in CloudTrail and
# add that ONE action on purpose. Do not "fix" it with *:*.
# Every group below says what it is for and where to tighten further.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  name       = var.cluster_name

  # State objects. With `use_lockfile = true`, Terraform also writes "<key>.tflock".
  state_bucket_arn = "arn:${local.partition}:s3:::${var.state_bucket_name}"
  state_key_arn    = "${local.state_bucket_arn}/${var.state_key}"
  state_lock_arn   = "${local.state_bucket_arn}/${var.state_key}.tflock"

  # Names created by envs/dev (see the plan): used to scope IAM/EKS/KMS/Logs.
  role_arns = [
    "arn:${local.partition}:iam::${local.account_id}:role/${local.name}-*",
    "arn:${local.partition}:iam::${local.account_id}:role/default-eks-node-group-*",
  ]
  policy_arns = [
    "arn:${local.partition}:iam::${local.account_id}:policy/${local.name}-cluster-ClusterEncryption*",
  ]
}

# =============================================================================
# PLAN ROLE (pull requests): read-only
# =============================================================================
data "aws_iam_policy_document" "plan" {
  # 1) Read the state. Plans run with -lock=false, so this role never needs
  #    write access to the bucket: a PR can't modify state even if it tried.
  statement {
    sid       = "ReadStateObject"
    actions   = ["s3:GetObject"]
    resources = [local.state_key_arn]
  }

  statement {
    sid       = "ListStatePrefix"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.state_key]
    }
  }

  # 2) Refresh = read the current state of what exists. Describe/Get/List only.
  #    TIGHTEN: these cannot be scoped to resources (Describe* APIs take "*"), but
  #    they can be pinned to the region. Note iam:Get*/List* reveals IAM metadata
  #    account-wide; drop to named resources if that is a concern.
  statement {
    sid = "RefreshReadOnly"
    actions = [
      "ec2:Describe*",
      "eks:Describe*",
      "eks:List*",
      "iam:Get*",
      "iam:List*",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "ssm:GetParameter",
    ]
    resources = ["*"]
    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region, "us-east-1"] # IAM is global and served from us-east-1
    }
  }
}

# =============================================================================
# APPLY ROLE (approval-gated environment): write access, scoped to envs/dev
# =============================================================================
data "aws_iam_policy_document" "apply" {
  # 1) State read/write + lock file. Scoped to the one state key, not the bucket.
  statement {
    sid       = "StateObjectReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_key_arn, local.state_lock_arn]
  }

  statement {
    sid       = "ListStatePrefix"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.state_key, "${var.state_key}.tflock"]
    }
  }

  # 2) Reads needed to refresh state and to resolve data sources.
  statement {
    sid = "RefreshReadOnly"
    actions = [
      "ec2:Describe*",
      "eks:Describe*",
      "eks:List*",
      "iam:Get*",
      "iam:List*",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "ssm:GetParameter",
    ]
    resources = ["*"]
  }

  # 3) EC2 / VPC writes: the VPC module (subnets, route tables, IGW, NAT, EIP,
  #    endpoints, default SG/NACL/route table) and the EKS node launch template.
  #    EC2 resources can't practically be scoped by ARN at creation time, so the
  #    guard rail is the region condition. TIGHTEN: add a `aws:ResourceTag/Project`
  #    condition on the Delete*/Modify* actions (tags are applied by default_tags).
  statement {
    sid = "Ec2NetworkingWrite"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint",
      "ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAclEntry", "ec2:ReplaceNetworkAclEntry", "ec2:ReplaceNetworkAclAssociation",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "Ec2SecurityGroupsAndLaunchTemplates"
    actions = [
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:ModifySecurityGroupRules",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateLaunchTemplate", "ec2:DeleteLaunchTemplate", "ec2:CreateLaunchTemplateVersion", "ec2:ModifyLaunchTemplate",
      "ec2:RunInstances", # needed by EKS to launch nodes from our launch template; remove if node creation works without it
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # 4) EKS: only THIS cluster's cluster / node group / add-on / access-entry ARNs.
  statement {
    sid = "EksClusterManagement"
    actions = [
      "eks:CreateCluster", "eks:DeleteCluster", "eks:UpdateClusterConfig", "eks:UpdateClusterVersion",
      "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion",
      "eks:CreateAddon", "eks:DeleteAddon", "eks:UpdateAddon",
      "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:UpdateAccessEntry",
      "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy",
      "eks:TagResource", "eks:UntagResource",
    ]
    resources = [
      "arn:${local.partition}:eks:${var.aws_region}:${local.account_id}:cluster/${local.name}",
      "arn:${local.partition}:eks:${var.aws_region}:${local.account_id}:nodegroup/${local.name}/*",
      "arn:${local.partition}:eks:${var.aws_region}:${local.account_id}:addon/${local.name}/*",
      "arn:${local.partition}:eks:${var.aws_region}:${local.account_id}:access-entry/${local.name}/*",
    ]
  }

  # 5) IAM roles: only the roles envs/dev creates, identified by name pattern.
  #    The biggest risk in any pipeline role is IAM write (privilege escalation),
  #    so this is deliberately narrow: no CreateUser, no access keys, no policies
  #    on anything outside these name patterns.
  statement {
    sid = "IamRolesManage"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy", "iam:UpdateRoleDescription",
      "iam:TagRole", "iam:UntagRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
    ]
    resources = local.role_arns
  }

  # Attaching policies is the escalation vector (attach AdministratorAccess to a
  # role you can assume). The condition limits it to the exact managed policies
  # this stack uses.
  statement {
    sid       = "IamAttachOnlyKnownPolicies"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = local.role_arns
    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = concat(
        [
          "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
          "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
          "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
          "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
          "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
        ],
        local.policy_arns,
      )
    }
  }

  statement {
    sid = "IamCustomPoliciesManage"
    actions = [
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
      "iam:TagPolicy", "iam:UntagPolicy",
    ]
    resources = local.policy_arns
  }

  # PassRole lets EKS/EC2 use the roles. Limited to those two services so the
  # roles can't be handed to, say, Lambda.
  statement {
    sid       = "IamPassRoleToEksAndEc2"
    actions   = ["iam:PassRole"]
    resources = local.role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }

  # The cluster's IRSA OIDC provider. Name pattern is oidc.eks.<region>.amazonaws.com/id/<id>.
  statement {
    sid = "IamClusterOidcProvider"
    actions = [
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint", "iam:AddClientIDToOpenIDConnectProvider",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/id/*"]
  }

  # First use of EKS in an account creates service-linked roles automatically.
  statement {
    sid       = "IamServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "autoscaling.amazonaws.com"]
    }
  }

  # 6) KMS for Kubernetes Secrets encryption. CreateKey can't be scoped to a key
  #    that doesn't exist yet; the others should be, once you know the key ID.
  #    TIGHTEN: after the first apply, add a condition on aws:ResourceTag/Project
  #    for the key-level actions.
  statement {
    sid = "KmsClusterKey"
    actions = [
      "kms:CreateKey", "kms:TagResource", "kms:UntagResource",
      "kms:PutKeyPolicy", "kms:EnableKeyRotation", "kms:DisableKeyRotation",
      "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "KmsAlias"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = ["arn:${local.partition}:kms:${var.aws_region}:${local.account_id}:alias/eks/${local.name}", "arn:${local.partition}:kms:${var.aws_region}:${local.account_id}:key/*"]
  }

  # 7) CloudWatch log group for control-plane logs (only used when the
  #    enable_control_plane_logs variable is true).
  statement {
    sid = "LogsControlPlaneGroup"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
      "logs:TagResource", "logs:UntagResource",
    ]
    resources = [
      "arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:/aws/eks/${local.name}/cluster",
      "arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:/aws/eks/${local.name}/cluster:*",
    ]
  }
}
