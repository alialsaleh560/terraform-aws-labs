terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-central-1"
}

locals {
  gh_repo = "repo:alialsaleh560@211395474/terraform-aws-labs@1446008343"
}

# -------Tell AWS to trust tokens issued by GitHub Actions------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}



resource "aws_iam_role" "github_plan" {
  name = "github-plan"

  # ----------------------------------Trust policy: whom can use this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "${local.gh_repo}:*"
        }
      }
    }]
  })
}



# 1. Read everything in the account (to refresh and compare)
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 2. Write and delete the lock file, only for the envs/ state files
resource "aws_iam_role_policy" "plan_state_lock" {
  name = "state-lock"
  role = aws_iam_role.github_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "arn:aws:s3:::tfstate-482112969377-euc1/envs/*"
    }]
  })
}

resource "aws_iam_role" "github_apply" {
  name = "github-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = [
            "${local.gh_repo}:environment:dev",
            "${local.gh_repo}:environment:prod",
          ]
        }
      }
    }]
  })
}


resource "aws_iam_role_policy_attachment" "apply_readonly" {
  role       = aws_iam_role.github_apply.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "apply_vpc" {
  role       = aws_iam_role.github_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}


resource "aws_iam_role_policy" "apply_state" {
  name = "state-write"
  role = aws_iam_role.github_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "arn:aws:s3:::tfstate-482112969377-euc1/envs/*"
    }]
  })
}