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
  description = "AWS region for the Fargate test registry."
  type        = string
  nullable    = false
}

variable "aws_account_id" {
  description = "AWS account authorized to host the Fargate test registry."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide a 12-digit AWS account ID."
  }
}

resource "aws_ecr_repository" "app" {
  for_each = toset(["nodejs", "go"])

  name                 = "1million-fargate-test-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "repository_urls" {
  description = "Private ECR repository URLs keyed by service."
  value       = { for name, repository in aws_ecr_repository.app : name => repository.repository_url }
}
