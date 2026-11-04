output "user_arns" {
  value = { for name, user in aws_iam_user.user : name => user.arn }
}