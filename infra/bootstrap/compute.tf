data "aws_ssm_parameter" "amazon_linux" {
  name            = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  with_decryption = false
}

locals {
  app_tags = {
    Project     = "1million-testing"
    Environment = "lab"
    ManagedBy   = "terraform"
    Name        = "1million-nodejs-lab"
  }
}

# A launch template describes each machine; the Auto Scaling Group launches it.
resource "aws_launch_template" "app" {
  name_prefix   = "1million-nodejs-"
  description   = "Node.js lab machines managed by Auto Scaling"
  image_id      = data.aws_ssm_parameter.amazon_linux.value
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  # Public IPs provide outbound downloads in this lab without a NAT gateway.
  # Inbound API traffic is permitted only from the ALB security group.
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.app.id]
  }

  user_data = base64encode(templatefile("${path.module}/templates/startup.sh.tftpl", {
    aws_region     = var.aws_region
    repository_url = aws_ecr_repository.app.repository_url
    image_digest   = data.aws_ssm_parameter.app_image_digest.value
    nginx_config   = file("${path.module}/templates/nginx.conf")
    node_log_group = aws_cloudwatch_log_group.app["nodejs"].name
    cloudwatch_config = templatefile("${path.module}/templates/cloudwatch-agent.json.tftpl", {
      aws_region = var.aws_region
      log_groups = { for key, group in aws_cloudwatch_log_group.app : key => group.name }
    })
  }))

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      encrypted             = true
      delete_on_termination = true
    }
  }

  credit_specification {
    cpu_credits = "standard"
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume"])

    content {
      resource_type = tag_specifications.value
      tags          = local.app_tags
    }
  }

  tags = {
    Name = "1million-nodejs-launch-template"
  }
}
