# terraform-aws-labs

Infrastructure as Code labs on AWS using OpenTofu (Terraform compatible). I'm building these while studying for the AWS Solutions Architect Associate exam.

Each folder is its own project with its own state file, stored in S3.

## Projects

### tf-state-bootstrap
Creates the S3 bucket that holds the remote state for the other projects. The bucket has versioning, encryption, public access blocked, and prevent_destroy set. This project keeps its own state locally, so it isn't committed here.

### tf-lesson1
IAM users created from a map variable with for_each. Admin users get a read-only policy through a filtered for_each. The IAM code is a module called twice, once for dev and once for prod.

Covers: typed variables, validation, locals, for expressions, outputs, modules, moved blocks.

### tf-vpc
A VPC module spread across two availability zones in eu-central-1.

```
VPC 10.0.0.0/16
  eu-central-1a
    public   10.0.0.0/24   -> public route table -> internet gateway
    private  10.0.10.0/24  -> private route table (1a)
  eu-central-1b
    public   10.0.1.0/24   -> public route table -> internet gateway
    private  10.0.11.0/24  -> private route table (1b)
```

Each AZ has its own private route table so a NAT gateway can be added per AZ later. I left the NAT gateway out to keep costs at zero.

Covers: data sources, cidrsubnet, for_each over other resources, route tables and associations.

## Remote state

All projects use the S3 backend with a separate key per project (lesson1/, vpc/) and S3 native locking (use_lockfile).

## Running it

Needs OpenTofu or Terraform 1.10+ and AWS credentials set up with `aws configure`.

```
cd tf-state-bootstrap
tofu init
tofu apply

cd ../tf-vpc
tofu init
tofu plan
tofu apply
```

The bucket name in each backend.tf has to be changed to your own bucket.

## Next

- Security groups, EC2, IAM roles
- ALB and Auto Scaling
- RDS with Secrets Manager
- GitHub Actions to run plan on pull requests
