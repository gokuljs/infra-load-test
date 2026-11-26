variable "aws_region" {
  description = "AWS region for the experiment."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account approved for the experiment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "The AWS account ID must contain exactly 12 digits."
  }
}

variable "api_client_cidr" {
  description = "Public IPv4 address of the lab client, used for SSH access to app machines."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(cidrnetmask(var.api_client_cidr)) &&
      endswith(var.api_client_cidr, "/32")
    )
    error_message = "Provide one IPv4 address followed by /32."
  }
}

variable "asg_min_size" {
  description = "Minimum desired machine count; Auto Scaling returns toward this after traffic drops."
  type        = number
  default     = 2
  nullable    = false

  validation {
    condition     = var.asg_min_size == floor(var.asg_min_size) && var.asg_min_size >= 1 && var.asg_min_size <= 10
    error_message = "The minimum must be a whole number between 1 and 10."
  }
}

variable "asg_initial_size" {
  description = "Machine count at group creation. AWS manages desired capacity afterward."
  type        = number
  default     = 2
  nullable    = false

  validation {
    condition = (
      var.asg_initial_size == floor(var.asg_initial_size) &&
      var.asg_initial_size >= var.asg_min_size &&
      var.asg_initial_size <= var.asg_max_size
    )
    error_message = "The initial count must be a whole number between the minimum and maximum."
  }
}

variable "asg_max_size" {
  description = "Maximum desired machine count for this lab, capped at 10."
  type        = number
  default     = 10
  nullable    = false

  validation {
    condition = (
      var.asg_max_size == floor(var.asg_max_size) &&
      var.asg_max_size >= var.asg_min_size &&
      var.asg_max_size <= 10
    )
    error_message = "The maximum must be a whole number at least as large as the minimum and no more than 10."
  }
}

variable "asg_cpu_target" {
  description = "Average fleet CPU percentage that the target tracking scaling policy aims to maintain."
  type        = number
  default     = 50
  nullable    = false

  validation {
    condition     = var.asg_cpu_target >= 1 && var.asg_cpu_target <= 100
    error_message = "The CPU target must be between 1 and 100 percent."
  }
}

resource "aws_iam_instance_profile" "app" {
  name = "1million-nodejs-ec2-lab"
  role = aws_iam_role.app.name
}
