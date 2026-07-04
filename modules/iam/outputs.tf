output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (created by this module, or existing_oidc_provider_arn if create_oidc_provider is false)."
  value       = local.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL used for IRSA trust policy conditions (without the https:// scheme)."
  value       = local.oidc_provider_url_no_scheme
}

output "irsa_role_arns" {
  description = "Map of IRSA role key to IAM role ARN, for every built-in example enabled plus every entry in var.irsa_roles."
  value       = { for k, v in aws_iam_role.irsa : k => v.arn }
}

output "irsa_role_names" {
  description = "Map of IRSA role key to IAM role name, for every built-in example enabled plus every entry in var.irsa_roles."
  value       = { for k, v in aws_iam_role.irsa : k => v.name }
}

output "external_dns_role_arn" {
  description = "ARN of the External DNS IRSA role, or null if enable_external_dns_role is false."
  value       = var.enable_external_dns_role ? aws_iam_role.irsa["external_dns"].arn : null
}

output "load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IRSA role, or null if enable_load_balancer_controller_role is false."
  value       = var.enable_load_balancer_controller_role ? aws_iam_role.irsa["aws_load_balancer_controller"].arn : null
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IRSA role, or null if enable_cluster_autoscaler_role is false."
  value       = var.enable_cluster_autoscaler_role ? aws_iam_role.irsa["cluster_autoscaler"].arn : null
}
