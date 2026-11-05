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
  security_group_id = aws_security_group.web.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
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

resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = local.vpc.public_subnets_id[0]
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  # Require IMDSv2 (security best practice)
  metadata_options {
    http_tokens = "required"
  }

  # Script that runs once, on first boot
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    echo "<h1>Hello from $(hostname -f)</h1>" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOF

  user_data_replace_on_change = true

  tags = {
    Name = "web-server"
  }
}