terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region_name
}

# VPC Resources
resource "aws_vpc" "customVPC" {
  cidr_block = var.vpc_cidr
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.customVPC.id

  tags = {
    Name = "CustomVPC"
  }
}

resource "aws_route_table" "publicRT" {
  vpc_id = aws_vpc.customVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRT"
  }
}

resource "aws_subnet" "custom_public_subnet1" {
  vpc_id                  = aws_vpc.customVPC.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.az1

  tags = {
    Name = "PublicSubnet1"
  }
}

resource "aws_subnet" "custom_public_subnet2" {
  vpc_id                  = aws_vpc.customVPC.id
  cidr_block              = var.subnet2_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.az2

  tags = {
    Name = "PublicSubnet2"
  }
}

resource "aws_route_table_association" "public_subnet_association1" {
  subnet_id      = aws_subnet.custom_public_subnet1.id
  route_table_id = aws_route_table.publicRT.id
}

resource "aws_route_table_association" "public_subnet_association2" {
  subnet_id      = aws_subnet.custom_public_subnet2.id
  route_table_id = aws_route_table.publicRT.id
}

# Security Group for EC2
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-security-group"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.customVPC.id

  tags = {
    Name = "EC2SecurityGroup"
  }
}

resource "aws_security_group_rule" "ec2_sg_rule_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2_sg.id
}

resource "aws_security_group_rule" "ec2_sg_rule_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2_sg.id
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.customVPC.id

  tags = {
    Name = "ALBSecurityGroup"
  }
}

resource "aws_security_group_rule" "alb_sg_rule_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_sg.id
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
  description = "Security group for RDS instances"
  vpc_id      = aws_vpc.customVPC.id

  tags = {
    Name = "RDSSecurityGroup"
  }
}

resource "aws_security_group_rule" "rds_sg_rule_mysql" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds_sg.id
}

# Launch Configuration and Auto Scaling Group
resource "aws_launch_configuration" "toktam_lc" {
  name_prefix       = "toktam-lc-"
  image_id          = var.ami_id
  instance_type     = var.instance_type
  security_groups   = [aws_security_group.ec2_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "toktam_asg" {
  name                      = "toktam-asg"
  min_size                  = 2
  max_size                  = 10
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.custom_public_subnet1.id, aws_subnet.custom_public_subnet2.id]
  launch_configuration      = aws_launch_configuration.toktam_lc.name
  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete              = true

  tag {
    key                 = "Name"
    value               = "toktam-server"
    propagate_at_launch = true
  }
}

# Application Load Balancer
resource "aws_lb" "toktam_lb" {
  name               = "toktam-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.custom_public_subnet1.id, aws_subnet.custom_public_subnet2.id]

  tags = {
    Name = "ToktamLoadBalancer"
  }
}

resource "aws_lb_target_group" "toktam_target_group" {
  name     = "toktam-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.customVPC.id

  health_check {
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "ToktamTargetGroup"
  }
}

resource "aws_lb_listener" "toktam_lb_listener" {
  load_balancer_arn = aws_lb.toktam_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.toktam_target_group.arn
  }
}
