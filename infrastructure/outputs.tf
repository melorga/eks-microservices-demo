output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "node_groups" {
  description = "Map of EKS managed node groups"
  value       = module.eks.eks_managed_node_groups
}

output "fargate_profiles" {
  description = "Map of EKS Fargate profiles"
  value       = module.eks.fargate_profiles
}

output "cluster_addons" {
  description = "Map of cluster addons"
  value       = aws_eks_addon.addons
}

output "kubectl_config" {
  description = "kubectl config command to connect to the cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
