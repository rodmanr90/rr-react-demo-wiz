# =============================================================================
# Variables - Single Root Module
# =============================================================================

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "wiz-demo"
}

variable "deployment_name" {
  description = "Deployment identifier used for all per-deploy resource names (lowercase letters, digits, hyphens)"
  type        = string
  default     = ""

  validation {
    condition     = var.deployment_name == "" || can(regex("^[a-z0-9][a-z0-9-]{1,14}[a-z0-9]$", var.deployment_name))
    error_message = "deployment_name must be 3-16 chars, lowercase alphanumeric plus hyphen, and cannot start/end with hyphen."
  }
}

# -----------------------------------------------------------------------------
# Feature Toggles - Enable/Disable Major Components
# -----------------------------------------------------------------------------

variable "create_eks" {
  description = "Whether to create the EKS cluster"
  type        = bool
  default     = true
}

variable "create_react2shell" {
  description = "Whether to deploy the React2Shell demo scenario"
  type        = bool
  default     = true
}

variable "create_wiz_connector" {
  description = "Whether to create the Wiz AWS connector"
  type        = bool
  default     = true
}

variable "create_wiz_k8s_integration" {
  description = "Whether to deploy Wiz K8s integration (sensor, admission controller)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Wiz Defend Logging Configuration
# -----------------------------------------------------------------------------

variable "enabled_logs" {
  description = "Toggle for Wiz Defend log types. CloudTrail includes S3 Data Events."
  type = object({
    cloudtrail   = bool
    route53_logs = bool
  })
  default = {
    cloudtrail   = true
    route53_logs = true
  }
}

# -----------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# -----------------------------------------------------------------------------
# EKS Configuration
# -----------------------------------------------------------------------------

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "eks_node_instance_type" {
  description = "Instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

# -----------------------------------------------------------------------------
# React2Shell Scenario Configuration
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Name of the demo application"
  type        = string
  default     = "react2shell"
}

variable "app_replicas" {
  description = "Number of app replicas"
  type        = number
  default     = 1
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to access the app (your IP)"
  type        = list(string)
  default     = []
}

variable "ecr_image" {
  description = "ECR image URL (leave empty to use default)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Wiz Configuration
# -----------------------------------------------------------------------------

variable "wiz_tenant_id" {
  description = "Wiz tenant ID for AWS connector trust"
  type        = string
  default     = ""
}

variable "wiz_trusted_arn" {
  description = "Wiz AssumeRoleDelegator ARN for AWS connector"
  type        = string
  default     = ""
}

variable "wiz_client_environment" {
  description = "Wiz environment for in-cluster components (passed as WIZ_ENV to Wiz Helm charts). Example: prod, commercial, gov"
  type        = string
  default     = "prod"
}

variable "wiz_sensor_enabled" {
  description = "Enable Wiz runtime sensor"
  type        = bool
  default     = true
}

variable "wiz_admission_controller_enabled" {
  description = "Enable Wiz admission controller"
  type        = bool
  default     = true
}

variable "wiz_kubernetes_integration_chart_version" {
  description = "Pinned wiz-kubernetes-integration Helm chart version for reproducible demos"
  type        = string
  default     = "0.3.13"
}


variable "tenant_image_pull_username" {
  description = "Username for pulling Wiz images"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tenant_image_pull_password" {
  description = "Password for pulling Wiz images"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Wiz Scanner IPs (for NetworkPolicy)
# -----------------------------------------------------------------------------

variable "dynamic_scanner_ipv4s_develop" {
  description = "Wiz scanner IPs for develop tenant"
  type        = string
  default     = "54.153.167.0/32,54.206.253.144/32,54.66.162.244/32,13.238.102.51/32,54.66.150.182/32,3.24.191.170/32"
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "WizDemo"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}
