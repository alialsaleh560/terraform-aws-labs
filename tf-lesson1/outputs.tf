locals {
  admins = [for name, u in var.users : name if u.admin]
}

output "admin_names" {
  value = local.admins
}


output "dev_user_arns" {
  value = module.dev_team.user_arns
}

output "prod_user_arns" {
  value = module.prod_team.user_arns
}

output "bucket_name" {
  value = aws_s3_bucket.team.bucket
}
