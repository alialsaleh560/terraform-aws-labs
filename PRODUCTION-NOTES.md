# Lab vs production

These labs are built to be cheap and easy to tear down. This file lists what I would change if the same infrastructure were running a real workload, and why.

## State (tf-state-bootstrap)

| Lab | Production |
|---|---|
| One bucket, versioning, SSE-S3 encryption, public access blocked, S3 native locking | Same, plus a customer managed KMS key, a bucket policy that only allows the CI role and a small admin group, and access logging |
| Bootstrap state kept on my laptop | Bootstrap state migrated into the bucket after the first apply, or the bucket created once by hand and imported |
| One account for everything | A separate state bucket per AWS account (dev, staging, prod), so a mistake in dev can't touch prod state |

## Identity (tf-lesson1, tf-ci-oidc)

| Lab | Production |
|---|---|
| IAM users created by Terraform | No IAM users for people. Humans sign in through IAM Identity Center (SSO) and assume roles |
| My own admin user with long-term access keys for local work | Short-lived credentials from SSO for local work |
| CI already uses OIDC with no stored keys (github-plan and github-apply roles) | Same |
| AWS managed policies (ReadOnlyAccess, AmazonVPCFullAccess) | Custom least-privilege policies with only the actions each project uses, reviewed in pull requests |
| One apply role trusted by both the dev and prod environments | A separate apply role per environment, ideally in separate AWS accounts, so a dev job can never touch prod |

## Network (tf-vpc)

| Lab | Production |
|---|---|
| No NAT gateway, to stay free | One NAT gateway per AZ, so private subnets can reach the internet and one AZ failure doesn't cut off the other |
| Web servers in public subnets | Web servers in private subnets. Only the ALB is in public subnets |
| No VPC endpoints | Gateway endpoints for S3 and DynamoDB (free), interface endpoints for SSM and Secrets Manager where traffic or security justifies it |
| No logging | VPC Flow Logs to CloudWatch or S3 |
| Hand-written VPC module | Usually the community module terraform-aws-modules/vpc, pinned to a version |

## Application (tf-app)

| Lab | Production |
|---|---|
| HTTP on port 80 | HTTPS on 443 with an ACM certificate, and port 80 redirecting to 443 |
| ALB DNS name used directly | A Route 53 record pointing at the ALB, so the URL doesn't change when the ALB is replaced |
| No WAF | AWS WAF on the ALB with managed rule groups |
| nginx installed by user_data at every boot | A pre-built AMI (Packer or EC2 Image Builder) so instances start faster and are identical |
| Fixed desired capacity of 2 | A target tracking scaling policy, for example average CPU at 50 percent |
| Launch template changes only apply to new instances | instance_refresh on the ASG so a template change rolls out gradually |
| deletion_protection off on the ALB | On |

## Database (tf-db)

| Lab | Production |
|---|---|
| skip_final_snapshot = true | false, with final_snapshot_identifier set |
| deletion_protection = false | true |
| No lifecycle block | lifecycle { prevent_destroy = true } |
| multi_az = false | true |
| Default backups | backup_retention_period of 7 to 35 days, backup and maintenance windows set to low-traffic hours |
| Default storage encryption | storage_encrypted = true with a customer managed KMS key. This can't be enabled later without rebuilding the database, so it is set from the first apply, even in dev |
| Fixed 20 GB | max_allocated_storage set so storage grows automatically |
| No monitoring | Performance Insights, enhanced monitoring, PostgreSQL logs exported to CloudWatch, alarms on CPU, storage and connections |
| Changes apply right away | apply_immediately = false so restarts happen in the maintenance window |
| Master password in Secrets Manager (kept) | Same, plus a separate application user with only the permissions it needs, instead of using the master user |

## Connecting the projects

| Lab | Production |
|---|---|
| db-sg allows 5432 from the whole VPC CIDR | db-sg allows 5432 only from the application's security group |
| | That rule lives in the app project, because the app already depends on the database project. Putting it in the database project would make the two projects depend on each other |
| | When replacing a rule, add the new one first, apply, then remove the old one, so the connection never drops |
| Destroy order learned by trial | Documented order: destroy what reads other projects first (app, then db, then vpc) |

## Workflow (CI/CD)

| Lab | Production |
|---|---|
| Pull requests run fmt, validate and plan, and the plan is posted as a comment | Same, plus tflint and a security scan (Checkov or Trivy) |
| Merge to master applies dev automatically, then prod after a manual approval | Same, with at least one reviewer who is not the author ("prevent self-review" on) |
| Apply jobs plan and apply in the same job (plan -out, then apply the file) | Same, or apply the exact plan file that was reviewed on the PR, stored as a build artifact |
| Branch ruleset on master requiring a PR and passing checks | Same, plus required reviews and CODEOWNERS for sensitive folders such as tf-ci-oidc |
| CI only plans and applies envs/ | Every project goes through CI. Nothing is applied from a laptop, except the one-time bootstrap |
| dev and prod in one AWS account | Separate accounts, sharing the same modules with different variables |
| A few tags set per module | Required tags on every resource (environment, owner, project, cost center), set once with default_tags on the provider |
| Manual cost checks | AWS Budgets alerts and cost reports by tag |
