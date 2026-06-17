# outputs.tf — values other modules or the root module need:
#   - cluster_name      used by `aws eks update-kubeconfig --name ...`
#   - cluster_endpoint   the API server URL, useful for debugging/verification
#   - cluster_ca         certificate authority data, needed if kubeconfig is
#                          generated manually instead of via the AWS CLI helper

output "cluster_name" {
  description = "EKS cluster name — pass to 'aws eks update-kubeconfig --name <this>'"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_role_arn" {
  description = "ARN of the worker node IAM role"
  value       = aws_iam_role.node.arn
}
