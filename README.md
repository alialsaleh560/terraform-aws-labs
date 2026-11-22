# terraform-aws-labs

Infrastructure as Code labs on AWS using OpenTofu (Terraform compatible). I'm building these while studying for the AWS Solutions Architect Associate exam.

Each folder is its own project with its own state file in S3. Changes go through pull requests: CI checks and plans every PR, and merging to master applies the environments, with a manual approval for prod.

See [PRODUCTION-NOTES.md](PRODUCTION-NOTES.md) for what I would change in a production setup.

## Projects

| Folder | What it builds |
|---|---|
| tf-state-bootstrap | S3 bucket for remote state |
| tf-ci-oidc | GitHub OIDC provider and the IAM roles CI uses |
| envs/dev, envs/prod | VPCs for each environment, using terraform-aws-modules/vpc |
| tf-lesson1 | IAM users from a module called once per environment |
| tf-vpc | My own multi-AZ VPC module (used by tf-app and tf-db) |
| tf-app | Load balancer and Auto Scaling Group of web servers |
| tf-db | RDS PostgreSQL with the password in Secrets Manager |

### tf-state-bootstrap
Creates the S3 bucket that holds the state for every other project. Versioning, encryption, public access blocked and prevent_destroy. Locking uses S3 native lock files. This project keeps its own state locally, so it isn't committed.

### tf-ci-oidc
Lets GitHub Actions reach AWS without stored keys.

- An OIDC provider for token.actions.githubusercontent.com
- github-plan: read-only, plus writing lock files under envs/. Trusted by any branch or PR of this repo
- github-apply: can manage VPC resources and write envs/ state. Trusted only by jobs running in the dev or prod GitHub environments, which only run from master

The trust policies use the newer subject format with owner and repository IDs (`repo:owner@id/repo@id:...`), which GitHub uses for repositories created after July 15, 2026.

### envs/dev and envs/prod
Each environment calls terraform-aws-modules/vpc (pinned to ~> 5.0) with its own values. main.tf and variables.tf are identical in both. The only differences are in terraform.tfvars and the backend key.

| | dev | prod |
|---|---|---|
| CIDR | 10.10.0.0/16 | 10.20.0.0/16 |
| Availability zones | 2 | 3 |
| State key | envs/dev/vpc.tfstate | envs/prod/vpc.tfstate |

Subnets are calculated from the CIDR with cidrsubnet, so a new environment only needs new values.

### tf-lesson1
IAM users created from a map variable with for_each. Admins get a policy through a filtered for_each. The IAM code is a module called twice, for dev and prod. Covers typed variables, validation, locals, for expressions, outputs, modules and moved blocks.

### tf-vpc
My own VPC module across two availability zones in eu-central-1, with public subnets routed to an internet gateway and one private route table per AZ (ready for a NAT gateway per AZ). Covers data sources, cidrsubnet and for_each over other resources.

### tf-app
Reads the VPC and database outputs with terraform_remote_state.

```
Internet -> ALB (alb-sg, both public subnets)
         -> target group with health checks on /
         -> Auto Scaling Group, min 2 / max 4, across 2 AZs (web-sg allows port 80 only from alb-sg)
```

- Launch template with Amazon Linux 2023 (AMI looked up with a data source), IMDSv2 required, nginx installed through user_data
- IAM role with SSM access, so instances are reached through Session Manager with no SSH and no keys
- Inline policy allowing the role to read only the database secret
- ELB health checks with a grace period. Terminating an instance by hand showed the ASG replacing it while the site stayed up

### tf-db
- PostgreSQL 16 on db.t4g.micro in the private subnets, not publicly accessible
- db-sg allows 5432 only from inside the VPC, with no egress rule
- manage_master_user_password = true, so RDS stores the password in Secrets Manager and it never appears in code or state
- Tested end to end: a web instance read the secret with its role and connected with psql

## CI/CD

`.github/workflows/terraform-ci.yml`

```
Pull request
  fmt -check ------------\
  validate (8 projects) --+--> plan envs/dev and envs/prod --> plan posted as a PR comment
                                (github-plan role)

Merge to master
  fmt + validate --> apply-dev --> waits for approval --> apply-prod
                     (github-apply role, dev and prod GitHub environments)
```

- validate runs `tofu init -backend=false`, so it needs no AWS access
- A branch ruleset on master requires a pull request and passing checks
- apply jobs plan and apply the same saved plan file

## Dependencies between projects

```
tf-state-bootstrap  (state for everything)
tf-ci-oidc          (CI access)
envs/dev, envs/prod
tf-vpc <- tf-db <- tf-app
```

Destroy in reverse order of dependencies: tf-app, then tf-db, then tf-vpc. Destroying tf-db first breaks tf-app's terraform_remote_state references.

## Things that went wrong and what I learned

- An interrupted destroy left a stale state lock and resources that were deleted in AWS but still in state. The next plan's refresh caught the drift
- A copied environment folder with the old backend key would load the other environment's state and plan to replace it. Every new environment gets its own key
- The CI role was rejected with "Not authorized to perform sts:AssumeRoleWithWebIdentity". Printing the token's claims showed the new subject format with owner and repo IDs, and the trust policy was updated to match
- A tag added to dev but not prod showed up straight away in the plan comments, which is the point of posting plans on PRs

## Running it

Needs OpenTofu or Terraform 1.10+ and AWS credentials.

```
cd tf-state-bootstrap
tofu init
tofu apply

cd ../tf-ci-oidc
tofu init
tofu apply
```

The bucket name in each backend.tf and the repository IDs in tf-ci-oidc have to be changed to your own. After that, environment changes go through pull requests.

Run `tofu destroy` on anything you're not using. The ALB, instances and RDS cost money while running.

## Next

- Import, drift detection and troubleshooting
- Capstone 1: web platform on ECS Fargate with HTTPS, CI/CD and monitoring
- Capstone 2: automated security and cost guardrails with EventBridge, Lambda and SNS
