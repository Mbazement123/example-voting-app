variable "aws_region" {
  description = "AWS region containing the default VPC and EKS cluster."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Short name used in the cluster and IAM resource names."
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group."
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint. Restrict this for your account."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "github_actions_principal_arn" {
  description = "IAM user ARN used by GitHub Actions access keys and granted EKS cluster access."
  type        = string
}