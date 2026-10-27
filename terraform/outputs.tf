output "cluster_name" {
  value = aws_eks_cluster.app.name
}

output "cluster_region" {
  value = var.aws_region
}

output "cluster_endpoint" {
  value = aws_eks_cluster.app.endpoint
}