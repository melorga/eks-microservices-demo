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
    condition = contains(["dev", "stage", "prod"], var.environment)
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
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
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

variable "cluster_addons" {
  description = "Map of cluster addon configurations"
  type = map(object({
    version                 = string
    service_account_role_arn = string
  }))
  default = {
    coredns = {
      version                 = "v1.10.1-eksbuild.5"
      service_account_role_arn = null
    }
    kube-proxy = {
      version                 = "v1.29.0-eksbuild.1"
      service_account_role_arn = null
    }
    vpc-cni = {
      version                 = "v1.16.0-eksbuild.1"
      service_account_role_arn = null
    }
    aws-ebs-csi-driver = {
      version                 = "v1.26.0-eksbuild.1"
      service_account_role_arn = null
    }
  }
}
