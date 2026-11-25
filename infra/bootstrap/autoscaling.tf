resource "aws_autoscaling_group" "app" {
  name                      = "1million-nodejs-asg"
  min_size                  = var.asg_min_size
  desired_capacity          = var.asg_initial_size
  max_size                  = var.asg_max_size
  vpc_zone_identifier       = [aws_subnet.app.id, aws_subnet.app_second.id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 600
  default_instance_warmup   = 300
  wait_for_capacity_timeout = "15m"

  # Wait for healthy targets at creation only. An exact ongoing ELB count would
  # conflict with the capacity changes made by automatic scaling.
  min_elb_capacity = var.asg_initial_size

  launch_template {
    id      = aws_launch_template.app.id
    version = tostring(aws_launch_template.app.latest_version)
  }

  # Template updates affect new launches. Rolling existing machines is a
  # separate deployment step, not an automatic part of this scaling lab.
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
  ]

  dynamic "tag" {
    for_each = local.app_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    # Initial size applies at creation; do not reset AWS's scaling decisions.
    ignore_changes = [desired_capacity]
  }

  depends_on = [
    aws_route_table_association.app,
    aws_route_table_association.app_second,
    aws_vpc_security_group_ingress_rule.api,
    aws_vpc_security_group_egress_rule.https,
    aws_vpc_security_group_egress_rule.alb_app,
    aws_iam_role_policy.app_ecr_pull,
    aws_lb_listener.http,
  ]
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "1million-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value     = var.asg_cpu_target
    disable_scale_in = false
  }
}
