terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "dev_team" {
  source      = "./modules/iam-team"
  environment = "dev"
  users       = var.users
}

module "prod_team" {
  source      = "./modules/iam-team"
  environment = "prod"
  users       = { ali = { role = "devops", admin = true } }
}

moved {
  from = aws_iam_user.user
  to   = module.dev_team.aws_iam_user.user
}

moved {
  from = aws_iam_user_policy_attachment.admin
  to   = module.dev_team.aws_iam_user_policy_attachment.admin
}

# S3 bucket names must be globally unique, so add a random suffix
resource "random_pet" "suffix" {
  length = 2
}

resource "aws_s3_bucket" "team" {
  bucket = "${var.environment}-team-files-${random_pet.suffix.id}"
}
