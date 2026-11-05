output "vpc_check" {
  value = data.terraform_remote_state.vpc.outputs
}
