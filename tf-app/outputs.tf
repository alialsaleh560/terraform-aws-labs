output "vpc_check" {
  value = data.terraform_remote_state.vpc.outputs
}

output "alb_url" {
  value = "http://${aws_lb.web-alb.dns_name}"
}