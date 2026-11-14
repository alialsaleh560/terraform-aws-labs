terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-central-1"
}


data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "tfstate-482112969377-euc1"
    key    = "vpc/terraform.tfstate"
    region = "eu-central-1"
  }
}

locals {
  vpc = data.terraform_remote_state.vpc.outputs
}

data "aws_vpc" "main" {
  id = local.vpc.vpc_id
}

resource "aws_db_subnet_group" "main-db" {
  name       = "main-db-subnet-group"
  subnet_ids = local.vpc.private_subnets_id
  tags = {
    Name = "main-db subnet group"
  }
}

resource "aws_security_group" "db" {
  name        = "db-sg"
  description = "PostgreSQL from inside the VPC"
  vpc_id      = data.aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id = aws_security_group.db.id
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = data.aws_vpc.main.cidr_block
}

resource "aws_db_instance" "main" {
  identifier     = "lesson-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name                     = "appdb"
  username                    = "appadmin"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main-db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  skip_final_snapshot = true #only for lesson , never done in production
}