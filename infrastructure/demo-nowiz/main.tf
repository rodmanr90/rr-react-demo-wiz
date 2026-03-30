# =============================================================================
# Main - Single Root Module for Wiz Demo
# =============================================================================
# This file orchestrates all components in a single terraform apply:
# - VPC + EKS cluster
# - ECR repository
# - Wiz AWS permissions (IAM role)
# - AWS Load Balancer Controller
# - Wiz K8s integration (Terraform-managed Helm release)
# - React2Shell demo scenario (app + S3 bucket + IRSA)
#
# Benefits:
# - One terraform apply / destroy (no ordering issues)
# - No remote state dependencies
# - Reliable for demos

locals {
  # Use an explicit deployment name when provided (preferred for repeatable CI).
  # Fall back to a random suffix for backwards compatibility.
  suffix = var.deployment_name != "" ? var.deployment_name : random_id.this.hex

  # Resource naming - ALL resources use the suffix to avoid conflicts
  cluster_name = "${var.prefix}-${local.suffix}-eks"
  ecr_name     = "${var.prefix}-${local.suffix}-app"

  # Common tags
  tags = merge(var.common_tags, {
    Environment = var.environment
    Suffix      = local.suffix
  })
}

# Random ID for resource uniqueness
resource "random_id" "this" {
  byte_length = 3
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# VPC
# =============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 100 + i)]
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # Cost optimization for demo
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for EKS to discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = local.tags
}

# =============================================================================
# EKS Cluster
# =============================================================================
module "eks" {
  count   = var.create_eks ? 1 : 0
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint for demo simplicity
  cluster_endpoint_public_access = true

  # Enable IRSA
  enable_irsa = true

  # Enable cluster creator admin permissions
  enable_cluster_creator_admin_permissions = true

  # Control plane logging
  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  # EKS Addons
  cluster_addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  # Managed node group
  eks_managed_node_groups = {
    default = {
      name           = "demo-nodes"
      instance_types = [var.eks_node_instance_type]

      min_size     = 1
      max_size     = 3
      desired_size = 2

      # Custom launch template for IMDSv1 (demo vulnerability)
      use_custom_launch_template = true

      # INTENTIONAL VULNERABILITY: IMDSv1 enabled for credential theft demo
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "optional"
        http_put_response_hop_limit = 2
      }

      labels = {
        Environment = "Demo"
        Project     = "React2Shell"
      }

      tags = local.tags
    }
  }

  tags = local.tags
}

# =============================================================================
# Graceful Shutdown - Gives Kubernetes controllers time to clean up
# =============================================================================
# This is the key to avoiding orphaned resources (security groups, ENIs) on destroy.
# The destroy_duration gives the AWS LB Controller time to delete NLBs/ALBs and
# their associated security groups before the EKS cluster is destroyed.
resource "time_sleep" "wait_for_cluster" {
  count            = var.create_eks ? 1 : 0
  depends_on       = [module.eks]
  create_duration  = "10s"
  destroy_duration = "60s" # Increased from 30s for more reliable cleanup
}

# =============================================================================
# ECR Repository
# =============================================================================
resource "aws_ecr_repository" "app" {
  name                 = local.ecr_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}


# =============================================================================
# AWS Load Balancer Controller
# =============================================================================
module "aws_lb_controller_irsa_role" {
  count   = var.create_eks ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.cluster_name}-aws-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks[0].oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  count      = var.create_eks ? 1 : 0
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.1"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks[0].cluster_name
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
    value = module.aws_lb_controller_irsa_role[0].iam_role_arn
  }

  set {
    name  = "region"
    value = data.aws_region.current.name
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [
    time_sleep.wait_for_cluster, # Wait for cluster stability
    module.aws_lb_controller_irsa_role
  ]
}

# =============================================================================
# React2Shell Scenario - S3 Bucket with Sensitive Data
# =============================================================================
resource "aws_s3_bucket" "sensitive_data" {
  count  = var.create_react2shell ? 1 : 0
  bucket = "${var.app_name}-${local.suffix}-sensitive-data"

  tags = merge(local.tags, {
    DataClassification = "Sensitive"
    Purpose            = "WizDemo"
    Scenario           = "react2shell"
  })
}

resource "aws_s3_bucket_public_access_block" "sensitive_data" {
  count  = var.create_react2shell ? 1 : 0
  bucket = aws_s3_bucket.sensitive_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "sensitive_data" {
  count  = var.create_react2shell ? 1 : 0
  bucket = aws_s3_bucket.sensitive_data[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Upload fake sensitive data files (triggers Wiz data findings)
resource "aws_s3_object" "customer_data" {
  count  = var.create_react2shell ? 1 : 0
  bucket = aws_s3_bucket.sensitive_data[0].id
  key    = "pii/customer-data.txt"
  source = "../../scenarios/react2shell/aws/data/customer-data.txt"
  etag   = filemd5("../../scenarios/react2shell/aws/data/customer-data.txt")
  tags   = local.tags
}

resource "aws_s3_object" "client_keys" {
  count  = var.create_react2shell ? 1 : 0
  bucket = aws_s3_bucket.sensitive_data[0].id
  key    = "pii/client_keys.txt"
  source = "../../scenarios/react2shell/aws/data/client_keys.txt"
  etag   = filemd5("../../scenarios/react2shell/aws/data/client_keys.txt")
  tags   = local.tags
}

resource "aws_s3_object" "aws_credentials" {
  count  = var.create_react2shell ? 1 : 0
  bucket = aws_s3_bucket.sensitive_data[0].id
  key    = "secrets/aws-credentials.txt"
  source = "../../scenarios/react2shell/aws/data/aws-credentials.txt"
  etag   = filemd5("../../scenarios/react2shell/aws/data/aws-credentials.txt")
  tags   = local.tags
}

resource "aws_s3_object" "api_keys" {
  count  = var.create_react2shell ? 1 : 0
  bucket = aws_s3_bucket.sensitive_data[0].id
  key    = "secrets/api-keys.txt"
  source = "../../scenarios/react2shell/aws/data/api-keys.txt"
  etag   = filemd5("../../scenarios/react2shell/aws/data/api-keys.txt")
  tags   = local.tags
}

resource "aws_s3_object" "customer_conversations" {
  count  = var.create_react2shell ? 1 : 0
  bucket = aws_s3_bucket.sensitive_data[0].id
  key    = "ai-training/customer-conversations.jsonl"
  source = "../../scenarios/react2shell/aws/data/customer-conversations.jsonl"
  etag   = filemd5("../../scenarios/react2shell/aws/data/customer-conversations.jsonl")
  tags   = local.tags
}

# =============================================================================
# React2Shell Application
# =============================================================================
module "react2shell_app" {
  count  = var.create_react2shell && var.create_eks ? 1 : 0
  source = "../../scenarios/react2shell/aws/modules/react2shell-app"

  name                      = "${var.app_name}-${local.suffix}"
  cluster_oidc_provider_arn = module.eks[0].oidc_provider_arn
  kubernetes_namespace      = "${var.app_name}-${local.suffix}"
  ecr_image                 = var.ecr_image != "" ? var.ecr_image : "${aws_ecr_repository.app.repository_url}:latest"
  replicas                  = var.app_replicas
  common_tags               = local.tags

  # NetworkPolicy configuration
  vpc_cidr          = module.vpc.vpc_cidr_block
  wiz_scanner_cidrs = var.dynamic_scanner_ipv4s_develop != "" ? [for cidr in split(",", var.dynamic_scanner_ipv4s_develop) : trimspace(cidr)] : []
  allowed_cidrs     = var.allowed_cidrs

  depends_on = [
    time_sleep.wait_for_cluster, # Wait for cluster stability
    helm_release.aws_load_balancer_controller
  ]
}
