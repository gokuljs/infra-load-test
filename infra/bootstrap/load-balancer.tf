resource "aws_lb" "app" {
  name               = "1million-lab"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.app.id, aws_subnet.app_second.id]

  depends_on = [
    aws_route_table_association.app,
    aws_route_table_association.app_second,
  ]
}

resource "aws_lb_target_group" "app" {
  name                          = "1million-nodejs-lab"
  port                          = 80
  protocol                      = "HTTP"
  target_type                   = "instance"
  vpc_id                        = aws_vpc.lab.id
  deregistration_delay          = 30
  load_balancing_algorithm_type = "round_robin"

  health_check {
    enabled             = true
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
