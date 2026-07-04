terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

locals {
  cluster_name = "${var.environment}-eks"

  default_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "eks"
      Repository  = "platform-foundation-aws"
    },
    var.tags,
  )

  cluster_autoscaler_tags = var.enable_cluster_autoscaler_tags ? {
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"               = "true"
  } : {}

  # Flattened (principal, policy) pairs so a principal with multiple
  # policy_arns produces one aws_eks_access_policy_association per policy.
  access_policy_associations = { for pair in flatten([
    for key, entry in var.cluster_access_entries : [
      for policy_arn in entry.policy_arns : {
        key           = "${key}-${replace(policy_arn, "/[^a-zA-Z0-9]/", "-")}"
        principal_arn = entry.principal_arn
        policy_arn    = policy_arn
      }
    ]
  ]) : pair.key => pair }
}

# ---------------------------------------------------------------------------
# Cluster IAM role. Distinct from the iam module's IRSA roles. This role
# is assumed by the EKS service itself, not by workloads; it's a
# cluster-infrastructure concern, not a workload-facing IRSA concern, so it
# lives here rather than in modules/iam. See docs/architecture.md.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.default_tags, {
    Name = "${local.cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Node IAM role. Scoped to exactly what a kubelet needs (worker node
# bootstrap, CNI, ECR pull). Workload AWS access goes through IRSA roles
# in the iam module instead; nothing here grants node-wide access beyond
# that. See docs/adr/ADR-004-why-irsa.md.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.default_tags, {
    Name = "${local.cluster_name}-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_node_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_read_only" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---------------------------------------------------------------------------
# Security Groups. Additional to the security group EKS creates and
# manages automatically for the cluster. See docs/networking.md and this
# module's README for the exact rules and why each one exists.
# ---------------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${local.cluster_name}-cluster"
  description = "EKS control plane ENIs (additional to the EKS-managed cluster security group)."
  vpc_id      = var.vpc_id

  tags = merge(local.default_tags, {
    Name = "${local.cluster_name}-cluster"
  })
}

resource "aws_security_group_rule" "cluster_egress_all" {
  security_group_id = aws_security_group.cluster.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Control plane egress to nodes and AWS APIs."
}

resource "aws_security_group_rule" "cluster_ingress_node_https" {
  security_group_id        = aws_security_group.cluster.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.node.id
  description              = "Nodes to control plane API server."
}

resource "aws_security_group" "node" {
  name        = "${local.cluster_name}-node"
  description = "EKS managed node groups."
  vpc_id      = var.vpc_id

  tags = merge(local.default_tags, {
    Name                                          = "${local.cluster_name}-node"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })
}

resource "aws_security_group_rule" "node_self_ingress" {
  security_group_id        = aws_security_group.node.id
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  source_security_group_id = aws_security_group.node.id
  description              = "Node-to-node communication (pod networking)."
}

resource "aws_security_group_rule" "node_egress_all" {
  security_group_id = aws_security_group.node.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Nodes need broad egress: image pulls, AWS API calls (via NAT), pod traffic."
}

resource "aws_security_group_rule" "node_ingress_cluster_https" {
  security_group_id        = aws_security_group.node.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.cluster.id
  description              = "Control plane to node kubelet HTTPS API."
}

resource "aws_security_group_rule" "node_ingress_cluster_extension_apis" {
  security_group_id        = aws_security_group.node.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 1025
  to_port                  = 65535
  source_security_group_id = aws_security_group.cluster.id
  description              = "Control plane to node extension API servers (metrics-server, admission webhooks)."
}

# ---------------------------------------------------------------------------
# Control plane logging. The log group is created here (not left for EKS
# to auto-create) so retention_in_days is actually enforced from the first
# log event, not applied after the fact. See docs/cost-optimization.md.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_in_days

  tags = merge(local.default_tags, {
    Name = "${local.cluster_name}-control-plane-logs"
  })
}

# ---------------------------------------------------------------------------
# EKS Cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  # checkov:skip=CKV_AWS_39:Public endpoint CIDR defaults to AWS's own
  # default (0.0.0.0/0) because there is no generic "safer" default
  # without caller-specific CIDRs (office/VPN ranges). Restrict via
  # endpoint_public_access_cidrs; see this module's README.
  # checkov:skip=CKV_AWS_58:Secrets envelope encryption requires a KMS key
  # ARN; the kms module is Planned (see modules/kms and docs/security.md).
  # Callers can supply their own key now via
  # cluster_encryption_config_kms_key_arn.
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  dynamic "encryption_config" {
    for_each = var.cluster_encryption_config_kms_key_arn != null ? [1] : []

    content {
      resources = ["secrets"]

      provider {
        key_arn = var.cluster_encryption_config_kms_key_arn
      }
    }
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.cluster_enabled_log_types

  tags = merge(local.default_tags, {
    Name = local.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ---------------------------------------------------------------------------
# Cluster access. Modern Access Entry API, no aws-auth ConfigMap and no
# kubernetes/helm provider required. See this module's README.
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "this" {
  for_each = var.cluster_access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn

  tags = local.default_tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = local.access_policy_associations

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.this]
}

# ---------------------------------------------------------------------------
# EKS Addons. vpc-cni, coredns, kube-proxy managed by Terraform instead of
# left at whatever version EKS defaulted to on cluster creation.
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "this" {
  for_each = var.cluster_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update

  tags = local.default_tags

  depends_on = [aws_eks_node_group.this]
}

# ---------------------------------------------------------------------------
# Managed Node Groups
# ---------------------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.environment}-${each.key}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = each.value.ami_type
  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types
  disk_size      = each.value.disk_size

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.default_tags, local.cluster_autoscaler_tags, {
    Name = "${var.environment}-eks-${each.key}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_read_only,
  ]

  lifecycle {
    # Cluster Autoscaler owns desired_size once it's running. Without this,
    # every terraform apply would fight the autoscaler back to whatever
    # desired_size was last set in this configuration.
    ignore_changes = [scaling_config[0].desired_size]
  }
}
