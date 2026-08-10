module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Existing VPC
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  # EKS API endpoint
  endpoint_public_access = true

  # enable creator access permission
  enable_cluster_creator_admin_permissions = true

  # access entries
  access_entries = {
    eks_admin = {
      principal_arn = "arn:aws:iam::953146140760:user/eks-admin"
    }
  }

  # EKS managed add-ons
  addons = {
    coredns = {
      most_recent = true
    }

    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent = true
      before_compute = true
    }

    eks-pod-identity-agent = {
      most_recent = true
      before_compute = true
    }

    aws-ebs-csi-driver = {
      most_recent = true

      pod_identity_association = [
        {
          role_arn        = aws_iam_role.ebs_csi.arn
          service_account = "ebs-csi-controller-sa"
        }
      ]
    }
  }

  # Managed node group for system workloads
  eks_managed_node_groups = {
    system = {
      name = "system-components"

      instance_types = ["t3.small"]

      min_size     = 2
      max_size     = 3
      desired_size = 2

      subnet_ids = var.public_subnet_ids

      capacity_type = "ON_DEMAND"

      labels = {
        workload = "system-components"
      }

      update_config = {
        max_unavailable = 1
      }
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}