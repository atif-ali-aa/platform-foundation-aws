output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "API server endpoint for the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster, used to configure kubectl/client access."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster. Feed this into the iam module's oidc_provider_issuer_url input to wire up IRSA."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "ID of the additional cluster security group this module creates and attaches to the control plane."
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "ID of the node security group. Attach this to anything (e.g. a database security group) that needs to allow traffic from cluster nodes."
  value       = aws_security_group.node.id
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role the EKS control plane assumes."
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role EKS managed node groups assume. Node-scoped only: workload AWS access goes through the iam module's IRSA roles instead."
  value       = aws_iam_role.node.arn
}

output "node_iam_role_name" {
  description = "Name of the node IAM role, for attaching additional policies if a specific deployment genuinely needs it."
  value       = aws_iam_role.node.name
}

output "node_group_names" {
  description = "Map of node group key to the actual EKS node group name."
  value       = { for k, v in aws_eks_node_group.this : k => v.node_group_name }
}

output "node_group_arns" {
  description = "Map of node group key to node group ARN."
  value       = { for k, v in aws_eks_node_group.this : k => v.arn }
}

output "node_group_autoscaling_group_names" {
  description = "Map of node group key to the underlying Auto Scaling Group name(s) EKS creates for each managed node group. Useful for referencing outside Cluster Autoscaler (e.g. custom CloudWatch alarms)."
  value       = { for k, v in aws_eks_node_group.this : k => v.resources[0].autoscaling_groups[*].name }
}

output "cluster_log_group_name" {
  description = "Name of the CloudWatch Logs group receiving control plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}
