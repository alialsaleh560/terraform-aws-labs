# One IAM user per person in terraform.tfvars
resource "aws_iam_user" "user" {
  for_each = var.users
  name     = "${var.environment}-${each.key}"

  tags = {
    Role  = each.value.role
    Admin = tostring(each.value.admin)
  }
}

# Only admins get a policy (a filtered for_each)
resource "aws_iam_user_policy_attachment" "admin" {
  for_each   = { for name, u in var.users : name => u if u.admin }
  user       = aws_iam_user.user[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}