resource "aws_security_group" "app" {
  name        = "1million-app"
  description = "Network access for the Node.js lab"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "1million-app"
  }
}

resource "aws_vpc_security_group_ingress_rule" "api" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP API and health checks from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.app.id
  description       = "SSH from the lab client"
  cidr_ipv4         = var.api_client_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS downloads and AWS service access"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_security_group" "alb" {
  name        = "1million-alb"
  description = "Testing IP to ALB, and ALB to app machines"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "1million-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Public HTTP"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward requests and health checks to Nginx"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}
