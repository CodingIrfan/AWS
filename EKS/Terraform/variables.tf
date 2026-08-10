variable "aws_region" {
  description = "Name of the region"
  type       = string
} 
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "public subnet IDs used by EKS"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}