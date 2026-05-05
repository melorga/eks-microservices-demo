variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stage, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "kubernetes_version" {
  description = "Kubernetes version. EKS 1.33 standard support ends 2026-07-29; 1.34 standard support ends ~2026-10-27. Source: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html"
  type        = string
  default     = "1.34"
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks permitted to reach the EKS public API endpoint. MUST be restricted in real use; the 0.0.0.0/0 default is for first-time bring-up only."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_managed_nodes" {
  description = "Enable managed node groups"
  type        = bool
  default     = false
}

variable "node_instance_types" {
  description = "Instance types for worker nodes"
  type        = list(string)
  default     = ["t3.medium"]

  validation {
    # t2.* is paravirtual / older generation; disallow.
    condition     = alltrue([for t in var.node_instance_types : !startswith(t, "t2.")])
    error_message = "t2.* instance types are not supported; use t3/t3a/m6i/c6i or newer."
  }
}

variable "min_nodes" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "desired_nodes" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# NOTE on addon versions:
# These defaults are reasonable May 2026 GA versions for K8s 1.34
# clusters, but the *exact* addon version available in any given AWS
# region drifts. Before applying, verify the latest compatible build with:
#   aws eks describe-addon-versions --kubernetes-version 1.34 --addon-name <name>
# and bump these defaults (or feed them in via tfvars / Dependabot).
variable "cluster_addons" {
  description = "Map of cluster addon configurations"
  type = map(object({
    version                  = string
    service_account_role_arn = optional(string)
  }))
  default = {
    coredns = {
      # TODO: verify via 'aws eks describe-addon-versions --kubernetes-version 1.34 --addon-name coredns'
      version = "v1.12.1-eksbuild.2"
    }
    kube-proxy = {
      # TODO: verify via 'aws eks describe-addon-versions --kubernetes-version 1.34 --addon-name kube-proxy' (confirm eksbuild suffix)
      version = "v1.34.0-eksbuild.2"
    }
    vpc-cni = {
      # TODO: verify via 'aws eks describe-addon-versions --kubernetes-version 1.34 --addon-name vpc-cni'
      version = "v1.19.5-eksbuild.3"
    }
    aws-ebs-csi-driver = {
      # TODO: verify via 'aws eks describe-addon-versions --kubernetes-version 1.34 --addon-name aws-ebs-csi-driver' (exact build couldn't be verified)
      version = "v1.39.0-eksbuild.1"
      # service_account_role_arn populated automatically in main.tf
      # from aws_iam_role for the EBS CSI IRSA role.
    }
  }
}

variable "state_bucket" {
  description = "S3 bucket for Terraform remote state. TODO: replace with your bucket."
  type        = string
  default     = "REPLACE-ME-tfstate-bucket"
}

variable "state_lock_table" {
  description = "DynamoDB table for Terraform state locking. TODO: replace with your table."
  type        = string
  default     = "REPLACE-ME-tfstate-lock"
}
