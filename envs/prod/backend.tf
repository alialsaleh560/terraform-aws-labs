terraform {
  backend "s3" {
    bucket       = "tfstate-482112969377-euc1"
    key          = "envs/prod/vpc.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}