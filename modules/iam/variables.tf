variable "environment" {
  description = "Deployment environment name. Used in resource naming and tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "create_oidc_provider" {
  description = "Whether to create the IAM OIDC identity provider. Set to false and supply existing_oidc_provider_arn if a provider for this issuer already exists (AWS allows only one OIDC provider per issuer URL per account)."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing IAM OIDC provider to use instead of creating one. Required when create_oidc_provider is false."
  type        = string
  default     = null

  validation {
    condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != null
    error_message = "existing_oidc_provider_arn must be set when create_oidc_provider is false."
  }
}

variable "oidc_provider_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (the eks module's cluster_oidc_issuer_url output), e.g. https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE. Required even when create_oidc_provider is false, since it's used to build IRSA trust policy conditions."
  type        = string

  validation {
    condition     = can(regex("^https://", var.oidc_provider_issuer_url))
    error_message = "oidc_provider_issuer_url must be a URL starting with https://."
  }
}

variable "oidc_provider_client_id_list" {
  description = "Audience values accepted by the OIDC provider. sts.amazonaws.com is correct for IRSA and should not need to change."
  type        = list(string)
  default     = ["sts.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# Generic, reusable IRSA roles
# ---------------------------------------------------------------------------

variable "irsa_roles" {
  description = "Additional IRSA roles to create beyond the built-in External DNS / AWS Load Balancer Controller / Cluster Autoscaler examples below. Keyed by a short role identifier used in the role name and in this module's map outputs."
  type = map(object({
    namespace       = string
    service_account = string
    policy_json     = string
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Example: External DNS
# ---------------------------------------------------------------------------

variable "enable_external_dns_role" {
  description = "Create an IRSA role for external-dns, scoped to the Route53 hosted zones in external_dns_hosted_zone_arns."
  type        = bool
  default     = false
}

variable "external_dns_service_account" {
  description = "Kubernetes namespace and service account name external-dns runs as. Must match the ServiceAccount external-dns is actually deployed with, or the trust policy won't match."
  type = object({
    namespace = string
    name      = string
  })
  default = {
    namespace = "kube-system"
    name      = "external-dns"
  }
}

variable "external_dns_hosted_zone_arns" {
  description = "Route53 hosted zone ARNs external-dns is allowed to modify. Required (non-empty) when enable_external_dns_role is true. This module does not fall back to a wildcard hosted zone match."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_external_dns_role || length(var.external_dns_hosted_zone_arns) > 0
    error_message = "external_dns_hosted_zone_arns must include at least one hosted zone ARN when enable_external_dns_role is true."
  }
}

# ---------------------------------------------------------------------------
# Example: AWS Load Balancer Controller
# ---------------------------------------------------------------------------

variable "enable_load_balancer_controller_role" {
  description = "Create an IRSA role for the AWS Load Balancer Controller."
  type        = bool
  default     = false
}

variable "load_balancer_controller_service_account" {
  description = "Kubernetes namespace and service account name the AWS Load Balancer Controller runs as."
  type = object({
    namespace = string
    name      = string
  })
  default = {
    namespace = "kube-system"
    name      = "aws-load-balancer-controller"
  }
}

# ---------------------------------------------------------------------------
# Example: Cluster Autoscaler
# ---------------------------------------------------------------------------

variable "enable_cluster_autoscaler_role" {
  description = "Create an IRSA role for Cluster Autoscaler, scoped to Auto Scaling Groups tagged for cluster_autoscaler_cluster_name."
  type        = bool
  default     = false
}

variable "cluster_autoscaler_service_account" {
  description = "Kubernetes namespace and service account name Cluster Autoscaler runs as."
  type = object({
    namespace = string
    name      = string
  })
  default = {
    namespace = "kube-system"
    name      = "cluster-autoscaler"
  }
}

variable "cluster_autoscaler_cluster_name" {
  description = "EKS cluster name used to scope Cluster Autoscaler's mutating actions to Auto Scaling Groups tagged k8s.io/cluster-autoscaler/<cluster_name> = owned. Required when enable_cluster_autoscaler_role is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_cluster_autoscaler_role || var.cluster_autoscaler_cluster_name != null
    error_message = "cluster_autoscaler_cluster_name must be set when enable_cluster_autoscaler_role is true."
  }
}

variable "tags" {
  description = "Additional tags merged into every resource this module creates, on top of the standard Environment/ManagedBy/Module/Repository tags (see docs/repository-standards.md)."
  type        = map(string)
  default     = {}
}
