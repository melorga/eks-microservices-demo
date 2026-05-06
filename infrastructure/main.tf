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

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  cluster_name = "${var.environment}-eks-cluster"

  common_tags = {
    Project     = "eks-microservices-demo"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ----------------------------------------------------------------------------
# VPC
# ----------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
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

# ----------------------------------------------------------------------------
# KMS key for EKS secrets encryption
# ----------------------------------------------------------------------------
resource "aws_kms_key" "eks" {
  description             = "KMS key for ${local.cluster_name} secrets envelope encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.cluster_name}"
  target_key_id = aws_kms_key.eks.key_id
}

# ----------------------------------------------------------------------------
# IRSA role for the AWS EBS CSI driver addon
# ----------------------------------------------------------------------------
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 6.6"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}

# ----------------------------------------------------------------------------
# IRSA role for AWS Load Balancer Controller (uses the official policy JSON)
# ----------------------------------------------------------------------------
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${local.cluster_name}-aws-load-balancer-controller"
  description = "Permissions required by the AWS Load Balancer Controller. Source: kubernetes-sigs/aws-load-balancer-controller iam_policy.json (committed at infrastructure/policies/aws-lb-controller.json)."
  policy      = file("${path.module}/policies/aws-lb-controller.json")

  tags = local.common_tags
}

module "aws_load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 6.6"

  role_name = "${local.cluster_name}-aws-load-balancer-controller"

  role_policy_arns = {
    main = aws_iam_policy.aws_load_balancer_controller.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.common_tags
}

# ----------------------------------------------------------------------------
# EKS Cluster
# ----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Endpoint controls
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.allowed_admin_cidrs
  endpoint_private_access      = true

  # Control plane logging
  enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  # Cluster secrets envelope encryption
  encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # Access entries (replaces the legacy aws-auth ConfigMap; introduced in module v20)
  authentication_mode = "API"

  access_entries = {
    caller_admin = {
      principal_arn = data.aws_caller_identity.current.arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Cluster addons configured here (replaces standalone aws_eks_addon resources)
  addons = {
    coredns = {
      addon_version = var.cluster_addons["coredns"].version
    }
    kube-proxy = {
      addon_version = var.cluster_addons["kube-proxy"].version
    }
    vpc-cni = {
      addon_version = var.cluster_addons["vpc-cni"].version
    }
    aws-ebs-csi-driver = {
      addon_version            = var.cluster_addons["aws-ebs-csi-driver"].version
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  # Fargate profiles
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        { namespace = "default" },
        { namespace = "kube-system" },
        { namespace = "monitoring" },
      ]
    }
  }

  # Optional managed node groups (Fargate-only by default)
  eks_managed_node_groups = var.enable_managed_nodes ? {
    main = {
      name           = "main"
      instance_types = var.node_instance_types

      # AL2 reaches EOL in EKS; AL2023 is the current default for new clusters.
      ami_type = "AL2023_x86_64_STANDARD"

      min_size     = var.min_nodes
      max_size     = var.max_nodes
      desired_size = var.desired_nodes
    }
  } : {}

  tags = local.common_tags
}

# ----------------------------------------------------------------------------
# Kubernetes / Helm providers
# ----------------------------------------------------------------------------
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# ----------------------------------------------------------------------------
# AWS Load Balancer Controller (Helm)
# ----------------------------------------------------------------------------
# NOTE: chart v3.x version-aligns with controller v3 (Gateway API GA).
# See https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.13/deploy/upgrade/ for v2->v3 migration notes.
# Existing Service+Ingress resources continue to work; Gateway API is opt-in.
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "3.2.2" # MAJOR bump from 1.10.0; refresh IAM policy from v3.2.2 release tag

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
    value = module.aws_load_balancer_controller_irsa_role.iam_role_arn
  }

  depends_on = [module.eks]
}

# ----------------------------------------------------------------------------
# Cluster log group (control plane logs)
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.eks.arn

  tags = local.common_tags
}

# ----------------------------------------------------------------------------
# Default StorageClass: gp3 + ebs.csi.aws.com + encrypted
# ----------------------------------------------------------------------------
resource "kubernetes_storage_class" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [module.eks]
}

# Strip the default-class annotation off the in-cluster gp2 SC if it exists
# (EKS ships gp2 as the default historically). Leaving the resource here so
# `terraform apply` is idempotent; comment out if your cluster has no gp2 SC.
resource "kubernetes_annotations" "gp2_not_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
  force = true

  depends_on = [module.eks]
}

# ----------------------------------------------------------------------------
# Helm: metrics-server
# ----------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.13.0"

  depends_on = [module.eks]
}

# ----------------------------------------------------------------------------
# Helm: cluster-autoscaler
#
# NOTE: For new EKS deployments in 2025+, prefer Karpenter
# (https://karpenter.sh/) over the legacy cluster-autoscaler. Karpenter
# provides faster scale-up, instance-type diversification, and bin-packing
# without managing per-AZ ASGs.
# ----------------------------------------------------------------------------
resource "helm_release" "cluster_autoscaler" {
  count = var.enable_managed_nodes ? 1 : 0

  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.57.0"

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
