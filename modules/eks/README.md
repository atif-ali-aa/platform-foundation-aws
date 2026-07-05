# eks

Amazon EKS cluster: managed node groups, OIDC issuer for IRSA, cluster and
node IAM roles, production security groups, control plane logging, EKS
addons, and modern Access Entry-based cluster access. No Karpenter, no
Helm/kubernetes-provider dependency.

Design reasoning lives in
[ADR-002](../../docs/adr/ADR-002-why-amazon-eks.md) and
[ADR-004](../../docs/adr/ADR-004-why-irsa.md). This README covers the
module's actual inputs, outputs, and the scope decisions specific to this
implementation.

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  environment         = "prod"
  kubernetes_version  = "1.30"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids

  node_groups = {
    default = {
      instance_types = ["m6i.large"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 3
      min_size       = 3
      max_size       = 6
    }
  }

  cluster_access_entries = {
    ci_deploy_role = {
      principal_arn = "arn:aws:iam::123456789012:role/ci-deploy"
      policy_arns   = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"]
    }
  }

  tags = {
    CostCenter = "platform"
  }
}

# Then wire the cluster's OIDC issuer into the iam module for IRSA:
module "iam" {
  source = "../../modules/iam"

  environment               = "prod"
  oidc_provider_issuer_url  = module.eks.cluster_oidc_issuer_url

  enable_load_balancer_controller_role = true
  enable_cluster_autoscaler_role       = true
  cluster_autoscaler_cluster_name      = module.eks.cluster_name
}
```

## Design decisions

- **No Karpenter.** Managed node groups plus Cluster Autoscaler is the
  production-ready autoscaling path this module ships. Karpenter is a
  materially different node-provisioning model and is explicitly scoped
  as a future, separate repository. See
  [ADR-002](../../docs/adr/ADR-002-why-amazon-eks.md).
- **No Helm chart installs, no `kubernetes`/`helm` Terraform providers.**
  This module produces the AWS-side infrastructure the AWS Load Balancer
  Controller and Cluster Autoscaler need to run (correct security group
  rules, node group ASG tags, the OIDC issuer for IRSA). It does not
  install the controllers themselves. Doing that via Terraform means
  Terraform talking directly to the cluster's Kubernetes API, which
  couples infrastructure and workload deployment lifecycles in exactly
  the way [ADR-003](../../docs/adr/ADR-003-why-gitops.md) argues against.
  See "Installing the controllers" below for what's actually required.
- **Modern Access Entry API, not the `aws-auth` ConfigMap.** Granting
  cluster access via `aws_eks_access_entry` and
  `aws_eks_access_policy_association` is pure AWS API: no `kubernetes`
  provider, no risk of Terraform and `kubectl` fighting over a ConfigMap.
  `access_config.bootstrap_cluster_creator_admin_permissions = true`
  means whoever runs `terraform apply` gets cluster-admin automatically;
  `cluster_access_entries` grants anyone else.
- **The control plane's CloudWatch Logs group is created by this module
  directly** (not left for EKS to auto-create) so `retention_in_days` is
  enforced from the first log event. See
  [docs/cost-optimization.md](../../docs/cost-optimization.md). This
  doesn't replace the planned `cloudwatch` module; it's a supporting
  resource this module fundamentally needs to function correctly, the
  same way `vpc` creates its own `aws_db_subnet_group`.
- **`scaling_config[0].desired_size` is excluded from Terraform's change
  detection** (`lifecycle.ignore_changes`). Once Cluster Autoscaler is
  running, it owns `desired_size`. Without this, every `terraform apply`
  would silently fight the autoscaler back to whatever value is in this
  configuration. `min_size`/`max_size` remain fully managed by Terraform.
- **Node groups are a required map input with no default.** Instance
  type, capacity type, and scaling bounds are real production decisions.
  A hidden default node group would be exactly the kind of "looks
  complete but wasn't actually decided" gap this repository's philosophy
  argues against.
- **EKS addons (`vpc-cni`, `coredns`, `kube-proxy`) are managed by
  Terraform**, not left at whatever version the cluster happened to
  launch with. Version drift on these is a real, easy-to-miss production
  issue.
- **Node groups use a launch template scoped to security groups and disk
  size only** (`aws_launch_template.node`). EKS managed node groups only
  auto-attach the security groups passed into the cluster's `vpc_config`;
  without a launch template, `aws_security_group.node` would be created
  but never actually applied to any node ENI. The launch template also
  enforces IMDSv2 (`http_tokens = "required"`) with
  `http_put_response_hop_limit = 1`, deliberately blocking pod-level
  access to instance metadata entirely, consistent with this module's
  IRSA-only workload credential story (see
  [ADR-004](../../docs/adr/ADR-004-why-irsa.md)).

## Reviewed CI exceptions

Seven `checkov` findings and eleven `tfsec` findings are suppressed
inline (`# checkov:skip=...` and `#tfsec:ignore:...` in `main.tf`)
rather than left to silently fail CI. Both tools flag some of the same
underlying design choices under different rule IDs. See
[docs/security.md](../../docs/security.md#ci-enforced-scanning) for the
exception policy:

- **`CKV_AWS_38`** / **`aws-eks-no-public-cluster-access-to-cidr`** on
  `aws_eks_cluster.this`: the public endpoint CIDR defaults to AWS's own
  default (`0.0.0.0/0`) because there's no generic "safer" default
  without caller-specific CIDRs (office/VPN ranges). Restrict via
  `endpoint_public_access_cidrs` per environment.
- **`CKV_AWS_39`** / **`aws-eks-no-public-cluster-access`** on
  `aws_eks_cluster.this`: public endpoint access is a deliberate,
  configurable choice (`endpoint_public_access`), not disabled outright,
  since some consumers need kubectl/CI access without a VPN or bastion
  into the VPC.
- **`CKV_AWS_58`** / **`aws-eks-encrypt-secrets`** on
  `aws_eks_cluster.this`: Secrets envelope encryption needs a KMS key
  ARN, and the `kms` module is Planned (not yet implemented). Callers can
  supply their own key now via `cluster_encryption_config_kms_key_arn`.
  This becomes the default once `kms` ships.
- **`CKV_AWS_37`** / **`aws-eks-enable-control-plane-logging`** on
  `aws_eks_cluster.this`: only `api`/`audit`/`authenticator` log types are
  enabled by default (see [docs/security.md](../../docs/security.md) and
  [ADR-002](../../docs/adr/ADR-002-why-amazon-eks.md)). `controllerManager`
  and `scheduler` are high-volume, low-signal for this platform's audit
  needs and can be added via `cluster_enabled_log_types` if a caller
  wants them.
- **`CKV_AWS_382`** / **`aws-ec2-no-public-egress-sgr`** on
  `aws_security_group_rule.cluster_egress_all` and `node_egress_all`:
  the control plane and nodes both need broad egress (AWS API calls,
  image pulls, NAT-routed internet traffic) that a generic module can't
  enumerate in advance. Inbound rules remain tightly scoped (see the
  security group table above).
- **`CKV_AWS_158`** on `aws_cloudwatch_log_group.cluster`: KMS encryption
  needs a key ARN, and the `kms` module is Planned. Callers can supply
  their own key now via `cluster_log_kms_key_arn`; logs are still
  encrypted at rest with the CloudWatch Logs default key.

## Installing the controllers

This module gets you to the point where installing the AWS Load Balancer
Controller and Cluster Autoscaler is a standard Helm install with an IRSA
role ARN. It doesn't do that install for you:

```bash
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$(terraform output -raw cluster_name) \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform output -raw load_balancer_controller_role_arn)"

helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=$(terraform output -raw cluster_name) \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform output -raw cluster_autoscaler_role_arn)"
```

(`load_balancer_controller_role_arn` and `cluster_autoscaler_role_arn`
are outputs of the `iam` module, not this one.) A reference composition
showing this end-to-end is planned for `examples/` once that milestone
ships. See [docs/gitops.md](../../docs/gitops.md) for the fuller
reasoning on why workload-layer installs live outside this repository's
Terraform.

## Security groups

Beyond the security group EKS creates and manages automatically for the
cluster, this module creates and attaches its own cluster and node
security groups with the minimum rules AWS documents as required:

| Rule | Direction | Port | Source/Destination |
| --- | --- | --- | --- |
| Control plane egress | egress | all | `0.0.0.0/0` |
| Control plane to node HTTPS | ingress | 443 | node security group |
| Node to node | ingress | all | node security group (self) |
| Node egress | egress | all | `0.0.0.0/0` |
| Node from control plane HTTPS (kubelet) | ingress | 443 | cluster security group |
| Node from control plane extension APIs | ingress | 1025-65535 | cluster security group |

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `environment` | Deployment environment name (`dev`, `staging`, `prod`). | `string` | n/a | yes |
| `kubernetes_version` | EKS Kubernetes minor version, e.g. `"1.30"`. | `string` | n/a | yes |
| `vpc_id` | VPC ID for cluster/node security groups. | `string` | n/a | yes |
| `private_subnet_ids` | Private subnets for control-plane ENIs and node groups. | `list(string)` | n/a | yes |
| `node_groups` | Managed node groups, keyed by name. At least one required. | `map(object)` | n/a | yes |
| `endpoint_private_access` | Enable private API endpoint access. | `bool` | `true` | no |
| `endpoint_public_access` | Enable public API endpoint access. | `bool` | `true` | no |
| `endpoint_public_access_cidrs` | CIDRs allowed to reach the public endpoint. | `list(string)` | `["0.0.0.0/0"]` | no |
| `cluster_enabled_log_types` | Control plane log types shipped to CloudWatch. | `list(string)` | `["api", "audit", "authenticator"]` | no |
| `cluster_log_retention_in_days` | CloudWatch Logs retention for control plane logs. | `number` | `365` | no |
| `cluster_encryption_config_kms_key_arn` | KMS key for Secrets envelope encryption. | `string` | `null` | no |
| `cluster_log_kms_key_arn` | KMS key for encrypting the control plane CloudWatch Logs group. | `string` | `null` | no |
| `cluster_access_entries` | Additional IAM principals to grant cluster access. | `map(object)` | `{}` | no |
| `cluster_addons` | EKS addons to manage. | `map(object)` | `vpc-cni`, `coredns`, `kube-proxy` | no |
| `enable_cluster_autoscaler_tags` | Tag node group ASGs for Cluster Autoscaler discovery. | `bool` | `true` | no |
| `tags` | Additional tags merged into every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| --- | --- |
| `cluster_name` | Name of the EKS cluster. |
| `cluster_arn` | ARN of the EKS cluster. |
| `cluster_endpoint` | API server endpoint. |
| `cluster_certificate_authority_data` | Base64 CA data for client configuration. |
| `cluster_oidc_issuer_url` | OIDC issuer URL, feed into the `iam` module. |
| `cluster_security_group_id` | ID of the additional cluster security group. |
| `node_security_group_id` | ID of the node security group. |
| `cluster_iam_role_arn` | ARN of the control plane's IAM role. |
| `node_iam_role_arn` | ARN of the node IAM role. |
| `node_iam_role_name` | Name of the node IAM role. |
| `node_group_names` | Map of node group key to EKS node group name. |
| `node_group_arns` | Map of node group key to node group ARN. |
| `node_group_autoscaling_group_names` | Map of node group key to underlying ASG name(s). |
| `cluster_log_group_name` | CloudWatch Logs group name for control plane logs. |

## What this module deliberately does not do

- No Karpenter. See [ADR-002](../../docs/adr/ADR-002-why-amazon-eks.md).
- No Helm installs, no `kubernetes` or `helm` providers. See "Installing
  the controllers" above.
- No IRSA roles. Those are created by the `iam` module, which this
  module's `cluster_oidc_issuer_url` output feeds into.
- No Fargate profiles. This module is managed-node-group-only; Fargate
  is a different enough execution model (no node security group, no
  Cluster Autoscaler interaction) that bolting it on here would blur the
  module's scope rather than clarify it.
