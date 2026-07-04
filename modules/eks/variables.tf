variable "environment" {
  description = "Deployment environment name. Used in resource naming and tagging, and to derive the cluster name (<environment>-eks)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version, e.g. \"1.30\". No default. Pinning this deliberately is safer than inheriting whatever AWS currently defaults to, since EKS deprecates versions on its own schedule (see docs/adr/ADR-002-why-amazon-eks.md)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like \"1.30\" (major.minor, no patch)."
  }
}

variable "vpc_id" {
  description = "VPC ID (from the vpc module's vpc_id output) that the cluster and node security groups are created in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (from the vpc module's private_subnet_ids output) used for the cluster's control-plane ENIs and for managed node groups."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "private_subnet_ids must include at least 2 subnets across different AZs."
  }
}

variable "endpoint_private_access" {
  description = "Enable private access to the EKS API server endpoint from within the VPC."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public access to the EKS API server endpoint. Combine with endpoint_public_access_cidrs to restrict who can reach it."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API server endpoint when endpoint_public_access is true. Defaults to AWS's own default (unrestricted). Tighten this for staging/prod (see docs/security.md)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_enabled_log_types" {
  description = "EKS control plane log types to enable, shipped to CloudWatch Logs. See docs/security.md for why api/audit/authenticator are the production-relevant baseline."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "cluster_log_retention_in_days" {
  description = "CloudWatch Logs retention for the control plane log group. Must be one of the retention periods CloudWatch Logs actually supports."
  type        = number
  default     = 90

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, 0],
      var.cluster_log_retention_in_days
    )
    error_message = "cluster_log_retention_in_days must be a value CloudWatch Logs supports (see AWS documentation for aws_cloudwatch_log_group retention_in_days)."
  }
}

variable "cluster_encryption_config_kms_key_arn" {
  description = "KMS key ARN for envelope encryption of Kubernetes Secrets. No default. The kms module is currently Planned (see modules/kms), so callers must supply their own key ARN until it ships. Leave null to skip envelope encryption (secrets are still encrypted at rest by EBS/etcd defaults, just not with a customer-managed key)."
  type        = string
  default     = null
}

variable "cluster_access_entries" {
  description = "Additional IAM principals to grant EKS cluster access via the Access Entry API (no aws-auth ConfigMap involved). The principal that runs terraform apply already gets cluster-admin automatically via bootstrap_cluster_creator_admin_permissions."
  type = map(object({
    principal_arn = string
    policy_arns   = list(string)
  }))
  default = {}
}

variable "cluster_addons" {
  description = "EKS addons to manage via Terraform, keyed by addon name (vpc-cni, coredns, kube-proxy). addon_version left null resolves to the EKS-recommended version for this cluster's Kubernetes version."
  type = map(object({
    addon_version               = optional(string)
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
  }))
  default = {
    "vpc-cni"    = {}
    "coredns"    = {}
    "kube-proxy" = {}
  }
}

variable "node_groups" {
  description = "Managed node groups, keyed by a short name (e.g. \"default\", \"spot\"). At least one is required. This module does not default to a hidden node group, since sizing/capacity type is a real production decision the caller has to make deliberately."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    disk_size      = optional(number, 50)
    desired_size   = number
    min_size       = number
    max_size       = number
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))

  validation {
    condition     = length(var.node_groups) >= 1
    error_message = "node_groups must define at least one node group."
  }

  validation {
    condition     = alltrue([for k, v in var.node_groups : contains(["ON_DEMAND", "SPOT"], v.capacity_type)])
    error_message = "each node group's capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for k, v in var.node_groups : v.min_size <= v.desired_size && v.desired_size <= v.max_size])
    error_message = "each node group must satisfy min_size <= desired_size <= max_size."
  }
}

variable "enable_cluster_autoscaler_tags" {
  description = "Apply the k8s.io/cluster-autoscaler/<cluster-name>=owned and k8s.io/cluster-autoscaler/enabled=true tags to every managed node group's underlying Auto Scaling Group, so Cluster Autoscaler can discover them. Disable only if you're not running Cluster Autoscaler at all."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged into every resource this module creates, on top of the standard Environment/ManagedBy/Module/Repository tags (see docs/repository-standards.md)."
  type        = map(string)
  default     = {}
}
