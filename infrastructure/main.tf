terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "eks-microservices-demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "eks-microservices-demo"
    }
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  cluster_name = "${var.environment}-eks-cluster"
  
  common_tags = {
    Project     = "eks-microservices-demo"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# VPC
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.environment}-eks-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment == "dev"
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.common_tags
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Fargate profiles
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "default"
        },
        {
          namespace = "kube-system"
        },
        {
          namespace = "monitoring"
        }
      ]
    }
  }

  # Managed node groups for workloads that require EC2
  eks_managed_node_groups = var.enable_managed_nodes ? {
    main = {
      name           = "main"
      instance_types = var.node_instance_types
      
      min_size     = var.min_nodes
      max_size     = var.max_nodes
      desired_size = var.desired_nodes

      vpc_security_group_ids = [aws_security_group.additional_sg.id]
    }
  } : {}

  tags = local.common_tags
}

# Additional security group for worker nodes
resource "aws_security_group" "additional_sg" {
  name_prefix = "${local.cluster_name}-additional-sg"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = local.common_tags
}

# EKS Addons
resource "aws_eks_addon" "addons" {
  for_each = var.cluster_addons

  cluster_name             = module.eks.cluster_name
  addon_name               = each.key
  addon_version            = each.value.version
  resolve_conflicts        = "OVERWRITE"
  service_account_role_arn = each.value.service_account_role_arn

  depends_on = [module.eks]

  tags = local.common_tags
}

# Data source for EKS cluster
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# Kubernetes provider
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Helm provider
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.0"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_load_balancer_controller.arn
  }

  depends_on = [module.eks]
}

# IAM role for AWS Load Balancer Controller
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${local.cluster_name}-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  role       = aws_iam_role.aws_load_balancer_controller.name
}

# CloudWatch Container Insights
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Metrics Server
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.11.0"

  depends_on = [module.eks]
}

# Cluster Autoscaler (if managed nodes are enabled)
resource "helm_release" "cluster_autoscaler" {
  count = var.enable_managed_nodes ? 1 : 0

  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  depends_on = [module.eks]
}
