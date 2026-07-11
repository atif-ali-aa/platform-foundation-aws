terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.54"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

locals {
  default_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "iam"
      Repository  = "platform-foundation-aws"
    },
    var.tags,
  )

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.this[0].arn : var.existing_oidc_provider_arn

  # IRSA trust policy conditions are keyed on the issuer URL without its
  # https:// scheme. That's how AWS names the OIDC provider's condition
  # context keys.
  oidc_provider_url_no_scheme = replace(var.oidc_provider_issuer_url, "https://", "")

  built_in_roles = merge(
    var.enable_external_dns_role ? {
      external_dns = {
        namespace       = var.external_dns_service_account.namespace
        service_account = var.external_dns_service_account.name
        policy_json     = data.aws_iam_policy_document.external_dns[0].json
      }
    } : {},
    var.enable_load_balancer_controller_role ? {
      aws_load_balancer_controller = {
        namespace       = var.load_balancer_controller_service_account.namespace
        service_account = var.load_balancer_controller_service_account.name
        policy_json     = data.aws_iam_policy_document.load_balancer_controller[0].json
      }
    } : {},
    var.enable_cluster_autoscaler_role ? {
      cluster_autoscaler = {
        namespace       = var.cluster_autoscaler_service_account.namespace
        service_account = var.cluster_autoscaler_service_account.name
        policy_json     = data.aws_iam_policy_document.cluster_autoscaler[0].json
      }
    } : {},
  )

  all_irsa_roles = merge(local.built_in_roles, var.irsa_roles)
}

# ---------------------------------------------------------------------------
# OIDC Provider
# ---------------------------------------------------------------------------

data "tls_certificate" "oidc" {
  count = var.create_oidc_provider ? 1 : 0

  url = var.oidc_provider_issuer_url
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.create_oidc_provider ? 1 : 0

  url             = var.oidc_provider_issuer_url
  client_id_list  = var.oidc_provider_client_id_list
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(local.default_tags, {
    Name = "${var.environment}-eks-oidc-provider"
  })
}

# ---------------------------------------------------------------------------
# IRSA roles: one aws_iam_role/aws_iam_policy pair per entry in
# local.all_irsa_roles (built-in examples below, plus anything the caller
# supplies via var.irsa_roles). Each role's trust policy is scoped to a
# specific namespace + service account; see docs/adr/ADR-004-why-irsa.md.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_trust" {
  for_each = local.all_irsa_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_scheme}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_scheme}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.all_irsa_roles

  name               = "${var.environment}-irsa-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.key].json

  tags = merge(local.default_tags, {
    Name                            = "${var.environment}-irsa-${each.key}"
    "kubernetes.io/namespace"       = each.value.namespace
    "kubernetes.io/service-account" = each.value.service_account
  })
}

resource "aws_iam_policy" "irsa" {
  for_each = local.all_irsa_roles

  name        = "${var.environment}-irsa-${each.key}"
  description = "Least-privilege policy for the ${each.key} IRSA role (system:serviceaccount:${each.value.namespace}:${each.value.service_account})."
  policy      = each.value.policy_json

  tags = local.default_tags
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = local.all_irsa_roles

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = aws_iam_policy.irsa[each.key].arn
}

# ---------------------------------------------------------------------------
# Example: External DNS. Route53 record management scoped to specific
# hosted zones, not a wildcard. See docs/networking.md / SECURITY.md for
# why this repository never defaults IAM scope to a wildcard resource.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "external_dns" {
  count = var.enable_external_dns_role ? 1 : 0

  statement {
    sid       = "ChangeResourceRecordSets"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = var.external_dns_hosted_zone_arns
  }

  statement {
    sid    = "ReadRoute53"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# Example: AWS Load Balancer Controller
#
# Modeled on the upstream aws-load-balancer-controller IAM policy's
# structure (broad read-only Describe/List calls, mutating actions scoped
# with the elbv2.k8s.aws/cluster resource-tag condition the controller
# itself applies). It is not a byte-for-byte copy of the upstream policy,
# which changes across controller versions. Before using this in a real
# account, diff it against the policy pinned to the controller version you
# deploy:
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/#iam-permissions
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "load_balancer_controller" {
  count = var.enable_load_balancer_controller_role ? 1 : 0

  statement {
    sid    = "DescribeReadOnly"
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CreateSecurityGroup"
    effect    = "Allow"
    actions   = ["ec2:CreateSecurityGroup"]
    resources = ["*"]
  }

  statement {
    sid       = "TagSecurityGroupOnCreate"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*:*:security-group/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
  }

  statement {
    sid    = "ManageControllerOwnedSecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "CreateElbResources"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
    ]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "ManageListenersAndRules"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageControllerOwnedElbResources"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetWebAcl",
    ]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "TagOnElbResourceCreate"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }
}

# ---------------------------------------------------------------------------
# Example: Cluster Autoscaler. Mutating actions scoped to Auto Scaling
# Groups tagged for this specific cluster; read-only Describe calls are
# necessarily account-wide (the API doesn't support scoping them further).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler_role ? 1 : 0

  statement {
    sid    = "DescribeReadOnly"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ScaleOwnedAutoScalingGroups"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_autoscaler_cluster_name}"
      values   = ["owned"]
    }
  }
}
