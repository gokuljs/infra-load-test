output "alb_dns_name" {
  description = "Public DNS name of the lab Application Load Balancer."
  value       = aws_lb.app.dns_name
}

output "app_url" {
  description = "HTTP API endpoint through Nginx; restricted to api_client_cidr."
  value       = "http://${aws_lb.app.dns_name}/api/ping"
}

output "asg_name" {
  description = "Auto Scaling Group to inspect for machine counts and scaling activity."
  value       = aws_autoscaling_group.app.name
}

output "dashboard_name" {
  description = "CloudWatch dashboard containing latency, CPU, errors, and fleet capacity."
  value       = aws_cloudwatch_dashboard.lab.dashboard_name
}

output "log_group_names" {
  description = "Centralized application logs, with separate streams for each EC2 instance."
  value       = { for key, group in aws_cloudwatch_log_group.app : key => group.name }
}

output "image_repository_url" {
  description = "Private ECR repository where Terraform publishes the app image."
  value       = aws_ecr_repository.app.repository_url
}
