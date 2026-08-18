#
# ---------------------------------------------------------
# Karpenter Node Role
# ---------------------------------------------------------
#
# This role is attached to EC2 instances launched by
# Karpenter.
#

resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-karpenter-node"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

#
# Permissions required by an EKS worker node
#

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

#
# Useful for troubleshooting / SSM access to nodes.
#

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#
# Instance profile used by Karpenter-launched EC2 instances.
#

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"

  role = aws_iam_role.karpenter_node.name

  tags = {
    Name        = "${var.cluster_name}-karpenter-node"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


#
# ---------------------------------------------------------
# Karpenter Controller Role
# ---------------------------------------------------------
#
# This role is assumed by the Karpenter controller Pod
# through EKS Pod Identity.
#

resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "pods.eks.amazonaws.com"
        }

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-karpenter-controller"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


#
# ---------------------------------------------------------
# Karpenter Controller Policy
# ---------------------------------------------------------
#

resource "aws_iam_policy" "karpenter_controller" {
  name        = "${var.cluster_name}-karpenter-controller"
  description = "Permissions for Karpenter to provision and manage EC2 nodes"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      #
      # ---------------------------------------------------
      # EC2 resource discovery
      # ---------------------------------------------------
      #

      {
        Sid    = "AllowRegionalReadActions"
        Effect = "Allow"

        Action = [
          "ec2:DescribeCapacityReservations",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribePlacementGroups",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ]

        Resource = "*"

        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },

      #
      # SSM is used to discover EKS optimized AMIs.
      #

      {
        Sid    = "AllowSSMReadActions"
        Effect = "Allow"

        Action = [
          "ssm:GetParameter"
        ]

        Resource = "arn:aws:ssm:${var.aws_region}::parameter/aws/service/*"
      },

      #
      # Pricing information
      #

      {
        Sid    = "AllowPricingReadActions"
        Effect = "Allow"

        Action = [
          "pricing:GetProducts"
        ]

        Resource = "*"
      },

      #
      # ---------------------------------------------------
      # EC2 provisioning
      # ---------------------------------------------------
      #

      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"

        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]

        Resource = [
          "arn:aws:ec2:${var.aws_region}::image/*",
          "arn:aws:ec2:${var.aws_region}::snapshot/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:security-group/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:capacity-reservation/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:placement-group/*"
        ]
      },

      #
      # Karpenter-created launch templates only
      #

      {
        Sid    = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect = "Allow"

        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]

        Resource = "arn:aws:ec2:${var.aws_region}:${var.account_id}:launch-template/*"

        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }

          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },

      #
      # Create EC2 resources with the Karpenter tags.
      #

      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"

        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate"
        ]

        Resource = [
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:fleet/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:volume/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:network-interface/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:launch-template/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:spot-instances-request/*"
        ]

        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                     = var.cluster_name
          }

          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },

      #
      # Allow tagging during resource creation.
      #

      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"

        Action = "ec2:CreateTags"

        Resource = [
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:fleet/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:volume/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:network-interface/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:launch-template/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:spot-instances-request/*"
        ]

        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                     = var.cluster_name
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          }

          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },

      #
      # Allow Karpenter to update its own instance tags.
      #

      {
        Sid    = "AllowScopedResourceTagging"
        Effect = "Allow"

        Action = "ec2:CreateTags"

        Resource = "arn:aws:ec2:${var.aws_region}:${var.account_id}:instance/*"

        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }

          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }

          StringEqualsIfExists = {
            "aws:RequestTag/eks:eks-cluster-name" = var.cluster_name
          }

          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = [
              "eks:eks-cluster-name",
              "karpenter.sh/nodeclaim",
              "Name"
            ]
          }
        }
      },

      #
      # ---------------------------------------------------
      # EC2 termination
      # ---------------------------------------------------
      #

      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"

        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]

        Resource = [
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${var.account_id}:launch-template/*"
        ]

        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }

          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },

      #
      # ---------------------------------------------------
      # IAM instance profile management
      # ---------------------------------------------------
      #

      {
        Sid    = "AllowPassingInstanceRole"
        Effect = "Allow"

        Action = "iam:PassRole"

        Resource = aws_iam_role.karpenter_node.arn

        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "ec2.amazonaws.com",
              "ec2.amazonaws.com.cn"
            ]
          }
        }
      },

      {
        Sid    = "AllowScopedInstanceProfileCreationActions"
        Effect = "Allow"

        Action = "iam:CreateInstanceProfile"

        Resource = "arn:aws:iam::${var.account_id}:instance-profile/*"

        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                     = var.cluster_name
            "aws:RequestTag/topology.kubernetes.io/region"            = var.aws_region
          }

          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },

      {
        Sid    = "AllowScopedInstanceProfileTagActions"
        Effect = "Allow"

        Action = "iam:TagInstanceProfile"

        Resource = "arn:aws:iam::${var.account_id}:instance-profile/*"

        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"            = var.aws_region

            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                     = var.cluster_name
            "aws:RequestTag/topology.kubernetes.io/region"            = var.aws_region
          }

          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },

      {
        Sid    = "AllowScopedInstanceProfileActions"
        Effect = "Allow"

        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ]

        Resource = "arn:aws:iam::${var.account_id}:instance-profile/*"

        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"            = var.aws_region
          }

          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },

      #
      # ---------------------------------------------------
      # EKS
      # ---------------------------------------------------
      #

      {
        Sid    = "AllowAPIServerEndpointDiscovery"
        Effect = "Allow"

        Action = "eks:DescribeCluster"

        Resource = "arn:aws:eks:${var.aws_region}:${var.account_id}:cluster/${var.cluster_name}"
      },

      #
      # ---------------------------------------------------
      # Instance profile discovery
      # ---------------------------------------------------
      #

      {
        Sid    = "AllowUnscopedInstanceProfileListAction"
        Effect = "Allow"

        Action = "iam:ListInstanceProfiles"

        Resource = "*"
      },

      {
        Sid    = "AllowInstanceProfileReadActions"
        Effect = "Allow"

        Action = "iam:GetInstanceProfile"

        Resource = "arn:aws:iam::${var.account_id}:instance-profile/*"
      },

      #
      # ---------------------------------------------------
      # Zonal Shift
      # ---------------------------------------------------
      #

      {
        Sid    = "AllowZonalShiftStatusReadOnly"
        Effect = "Allow"

        Action = "arc-zonal-shift:GetManagedResource"

        Resource = "*"

        Condition = {
          StringEquals = {
            "arc-zonal-shift:ResourceIdentifier" = "arn:aws:eks:${var.aws_region}:${var.account_id}:cluster/${var.cluster_name}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}


#
# ---------------------------------------------------------
# EKS Pod Identity Association
# ---------------------------------------------------------
#
# Karpenter controller:
#
# namespace: kube-system
# service account: karpenter
#

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "karpenter"

  role_arn = aws_iam_role.karpenter_controller.arn

  depends_on = [
    module.eks
  ]
}