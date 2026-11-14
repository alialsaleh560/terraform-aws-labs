terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-central-1"
}

#----------------------------------------------------------data---------

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "tfstate-482112969377-euc1"
    key    = "vpc/terraform.tfstate"
    region = "eu-central-1"
  }
}


data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}
#-------------------------------connection to db -data source and role policy-----------------------
data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    bucket = "tfstate-482112969377-euc1"
    key    = "db/terraform.tfstate"
    region = "eu-central-1"
  }
}

# Let the web role read ONLY the database secret
resource "aws_iam_role_policy" "read_db_secret" {
  name = "read-db-secret"
  role = aws_iam_role.web.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = data.terraform_remote_state.db.outputs.db_secret_arn
    }]
  })
}
#----------------------------------------------locals-----------------------------------
locals {
  vpc = data.terraform_remote_state.vpc.outputs
}

#-------------------------------------------------security groups---------

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow HTTP in, all traffic out"
  vpc_id      = local.vpc.vpc_id

  tags = {
    Name = "web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from anywhere"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb-sg.id
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
#----------------------------------------------alb-sg----------
resource "aws_security_group" "alb-sg" {
  name        = "alb-sg"
  description = "Allow HTTP in, all traffic out"
  vpc_id      = local.vpc.vpc_id

  tags = {
    Name = "alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb-http" {
  security_group_id = aws_security_group.alb-sg.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb-all" {
  security_group_id = aws_security_group.alb-sg.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}




resource "aws_iam_role" "web" {
  name = "web-ec2-role"

  # Trust policy: who is allowed to use this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# What the role is allowed to do: be managed by SSM Session Manager
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The wrapper EC2 needs in order to use the role
resource "aws_iam_instance_profile" "web" {
  name = "web-ec2-profile"
  role = aws_iam_role.web.name
}

#--------------------------------------------------------ec2 --------------------------------

resource "aws_launch_template" "web" {
  name_prefix   = "web-asg-ec2-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.web.name
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y nginx
    echo "<h1>Hello from $(hostname -f)</h1>" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOF
  )





  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-ec2"
    }
  }
}


#-----------------------------------------lb-target group
resource "aws_lb_target_group" "web-alb-tg" {
  name        = "web-ec2-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "web-alb-tg"
  }
}

resource "aws_lb" "web-alb" {
  name               = "main-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
  subnets            = local.vpc.public_subnets_id

  enable_deletion_protection = false

  tags = {
    Name = "main-web-alb"

  }
}

#-----------------------------------------listener--------------------------
resource "aws_lb_listener" "web-alb-http" {
  load_balancer_arn = aws_lb.web-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-alb-tg.arn
  }
}


resource "aws_autoscaling_group" "web-asg" {
  name_prefix = "web-asg-"

  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  vpc_zone_identifier = local.vpc.public_subnets_id

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns =[aws_lb_target_group.web-alb-tg.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 120
}