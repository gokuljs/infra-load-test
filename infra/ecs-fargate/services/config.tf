terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = "1million-testing"
      Environment = "fargate-test"
      ManagedBy   = "terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS region of the test services and image repositories."
  type        = string
  nullable    = false
}

variable "aws_account_id" {
  description = "AWS account authorized to host the test services and image repositories."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide a 12-digit AWS account ID."
  }
}

variable "client_cidrs" {
  description = "IPv4 CIDRs allowed to reach the test load balancer."
  type        = set(string)
  nullable    = false

  validation {
    condition = length(var.client_cidrs) > 0 && alltrue([
      for cidr in var.client_cidrs : try(
        can(cidrnetmask(cidr)) && cidrhost(cidr, 0) == split("/", cidr)[0] && !endswith(cidr, "/0"),
        false,
      )
    ])
    error_message = "Provide at least one canonical IPv4 client CIDR narrower than /0."
  }
}

variable "image_digests" {
  description = "ECR image digests keyed by nodejs and go."
  type        = map(string)
  nullable    = false

  validation {
    condition = toset(keys(var.image_digests)) == toset(["nodejs", "go"]) && alltrue([
      for digest in values(var.image_digests) : can(regex("^sha256:[0-9a-f]{64}$", digest))
    ])
    error_message = "Provide exactly the nodejs and go keys, each with a sha256 digest."
  }
}

variable "node_rollout" {
  description = "Pre-warm a second Node.js task and require one healthy task during a rolling release."
  type        = bool
  default     = false
  nullable    = false
}

variable "alarm_topic_arn" {
  description = "Optional ARN of an existing SNS topic for alarm notifications."
  type        = string
  default     = null
}

locals {
  name                 = "1million-fargate-test"
  app_port             = 3000
  max_tasks            = 4
  requests_per_minute  = 600
  log_retention_days   = 14
  apps = {
    nodejs = {
      listener_port          = 80
      min_tasks              = var.node_rollout ? 2 : 1
      deployment_min_healthy = var.node_rollout ? 50 : 0
    }
    go = {
      listener_port          = 8080
      min_tasks              = 2
      deployment_min_healthy = 50
    }
  }
}
