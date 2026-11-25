resource "aws_cloudwatch_dashboard" "lab" {
  dashboard_name = "1million-lab"

  dashboard_body = jsonencode({
    start          = "-PT1H"
    periodOverride = "inherit"
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Backend latency: p50 / p95 / p99 (seconds, until response headers)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          metrics = [for percentile in ["p50", "p95", "p99"] : [
            "AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", aws_lb.app.arn_suffix,
            "TargetGroup", aws_lb_target_group.app.arn_suffix,
            { stat = percentile, label = percentile },
          ]]
          yAxis = { left = { min = 0, label = "Seconds" } }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "Average fleet CPU (target: ${var.asg_cpu_target}%)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [[
            "AWS/EC2", "CPUUtilization",
            "AutoScalingGroupName", aws_autoscaling_group.app.name,
          ]]
          yAxis = { left = { min = 0, max = 100, label = "CPU (%)", showUnits = false } }
          annotations = {
            horizontal = [{ label = "Scaling target", value = var.asg_cpu_target }]
          }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "ALB requests per second"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix,
            { id = "m_requests", stat = "Sum", visible = false }],
            [{ expression = "m_requests / PERIOD(m_requests)", label = "Requests/second", id = "e_rps" }],
          ]
          yAxis = { left = { min = 0, label = "Requests/second", showUnits = false } }
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title   = "5xx responses per minute"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix,
            { id = "m_alb_errors", stat = "Sum", visible = false }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix,
              "TargetGroup", aws_lb_target_group.app.arn_suffix,
            { id = "m_target_errors", stat = "Sum", visible = false }],
            [{ expression = "FILL(m_alb_errors, 0)", label = "ALB 5xx", id = "e_alb_errors" }],
            [{ expression = "FILL(m_target_errors, 0)", label = "Application 5xx", id = "e_target_errors" }],
          ]
          yAxis = { left = { min = 0, label = "Responses/minute", showUnits = false } }
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 24, height = 6
        properties = {
          title   = "Fleet size: desired, in-service, pending, terminating, and limits"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [for metric in [
            "GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances",
            "GroupTerminatingInstances", "GroupMinSize", "GroupMaxSize",
            ] : [
            "AWS/AutoScaling", metric, "AutoScalingGroupName", aws_autoscaling_group.app.name,
          ]]
          yAxis = { left = { min = 0, label = "Instances", showUnits = false } }
        }
      },
    ]
  })
}
