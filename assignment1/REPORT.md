# Assignment 1 - Multi-environment deployment

## Introduction

This builds on my Week 7 Terraform (VPC, subnets, security group, one EC2 web server). I turned it into a module and used it for dev, staging and prod. Everything is deployed by one GitHub Actions workflow, `.github/workflows/assignment1-deploy.yml`, with approval gates and no long-lived AWS keys, only the Academy session credentials from `refresh-gha-creds.sh`.

## 1. Reusable module

`terraform/modules/webapp` builds the VPC, two public subnets, internet gateway, route table, security group, a t3.micro web server and a CloudWatch alarm.

- Inputs: `environment`, `owner`, `vpc_cidr`, `ami_id`, `instance_type`, `db_password_param`, `cpu_alarm_threshold`
- Outputs: `vpc_id`, `subnet_ids`, `web_instance_id`, `web_public_ip`, `web_url`, `cpu_alarm_name`, `db_password_length`

Names and tags use the environment, so three copies can live in one account. The AMI is an input so the module does not care how it is found (dev uses a fake one on LocalStack).

## 2. Environment directories

`dev/`, `staging/` and `prod/` each have a `main.tf` that calls the module, plus an `outputs.tf`. Each has its own backend key in the same S3 bucket so the states never collide:

| Env | State key | VPC CIDR | Alarm threshold | Runs on |
|---|---|---|---|---|
| dev | `assignment1/dev/terraform.tfstate` | 10.10.0.0/16 | 95 | LocalStack only |
| staging | `assignment1/staging/terraform.tfstate` | 10.20.0.0/16 | 90 | real AWS |
| prod | `assignment1/prod/terraform.tfstate` | 10.30.0.0/16 | 80 | real AWS |

The dev provider is hard-coded to the LocalStack endpoint, so it can never touch my real account. In CI it uses a local state file (a `backend_override.tf` made at run time) because the S3 backend needs real credentials.

## 3. GitHub Environments

- `staging`: no protection, so it applies on its own after a merge to `main`.
- `prod`: required reviewer (my account) and a deployment branch policy that only allows `main`.

In the workflow, the `staging` job has `environment: staging` and the `prod` job has `environment: prod` and `needs: staging`. Both only run on `main`, never on a pull request. Proof is in `evidence/` (`environments.txt`, `prod-approval.txt`, `pipeline-run.txt`). In run 45774026642 staging applied by itself, then prod sat on "waiting" until I approved it.

## 4. Scoped credentials and OIDC trust policy

The three secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) now exist only as secrets on the `staging` and `prod` environments. I deleted the repository-level copies (`evidence/environments.txt` shows none left). A job can only read them if it runs in that environment, so a prod job has to pass the reviewer and the branch rule first. The refresh command is now `./scripts/refresh-gha-creds.sh Automation-AD/acs730-coursework staging prod`.

The trust policy I would use for the prod role in a real AWS account (Academy blocks IAM writes, so I could not deploy it):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:Automation-AD/acs730-coursework:environment:prod"
        }
      }
    }
  ]
}
```

What each part prevents:

- **Principal (the OIDC provider):** only tokens signed by GitHub's identity provider can even try to use this role. A token from anywhere else is rejected.
- **Action `AssumeRoleWithWebIdentity`:** the role can only be taken with a web identity token, not with normal IAM user keys.
- **`aud` = `sts.amazonaws.com`:** the token must have been made for AWS STS. A token GitHub issued for some other service can't be replayed against AWS.
- **`sub` = `repo:Automation-AD/acs730-coursework:environment:prod`:** only jobs from this exact repo that run in the `prod` environment can assume the role. Another repo, a fork, a pull request job, a job on a feature branch or a job in `staging` all get a different `sub` and are denied. Since prod jobs only start after the reviewer approves and only from `main`, the role is behind the same gate.
- **`StringEquals`, not `StringLike`:** no wildcard, so `repo:Automation-AD/*` or `environment:*` can't match. A whole-repo wildcard would let any workflow in the repo, including one from a PR, deploy to prod.

The workflow would also need `permissions: id-token: write` and the `role-to-assume` input instead of the three secrets.

## 5. Real deployment

PR #9 merged to `main`. The workflow run on that push:

| Job | Result |
|---|---|
| fmt and validate (dev, staging, prod) | success |
| dev on LocalStack | success |
| deploy staging | success (automatic) |
| deploy prod | success (after my approval) |

Both environments are in account `077932765602` (`evidence/staging-output.txt`, `evidence/prod-output.txt`) and each web server answered with its own page (`evidence/web-check.txt`).

## 6. Secrets management

The db password is a SecureString in SSM Parameter Store, one per environment (`/acs730/assignment1/<env>/db_password`). I created them with the CLI and a random value, so the password is not in git. The module reads it with `data "aws_ssm_parameter"` and `with_decryption = true`. The output only shows its length (24 in staging and prod) so I can prove the read worked without printing it. One catch: the value still ends up in the Terraform state file, which is why the state bucket has encryption on.

## 7. CloudWatch alarm

`aws_cloudwatch_metric_alarm.cpu_high` in the module watches `CPUUtilization` (namespace `AWS/EC2`) on the web instance, average over 5 minutes, 2 periods, with a different threshold per environment (`evidence/cloudwatch-alarms.txt`). It has no alarm action since I have no SNS topic, so right now it only changes state. Prod showed INSUFFICIENT_DATA at first because the instance was only a few minutes old.

## 8. Recommendation: GitHub Actions or AWS-native?

For a team that is all-in on AWS with no multi-cloud plans, I would recommend an AWS-native pipeline (CodePipeline with CodeBuild, GitHub can still be the source repo). My reasons:

1. **Credentials.** In AWS-native the pipeline already runs as an IAM role, so there is no key to store or rotate. With GitHub Actions you need OIDC set up properly, and in this lab I could not even do that, so I used stored session credentials. That is the weakest part of what I built.
2. **Access to private stuff and auditing.** CodeBuild can run inside the team's VPC and reach private resources, and every action shows up in CloudTrail under one account. A GitHub runner is outside, so anything private needs a self-hosted runner.
3. **One vendor, one bill.** IAM, logs, approvals (CodePipeline manual approval) and alarms are all in the same place, and the team only has to look at one console. Actions adds another system to secure and another set of permissions to keep in sync.
4. **Cost.** CodeBuild is pay per minute and nothing is charged when idle.

GitHub Actions wins on the developer side: the YAML is easier, there is a big action marketplace, pull request checks and environment approvals are nice, and it is free for public repos. So I would pick GitHub Actions for a small team that values speed over control, and AWS-native once security or compliance matters.

## 9. Teardown

I ran `terraform destroy` for staging and prod and deleted the SSM parameters, which Terraform does not manage. Output is in `evidence/teardown.txt`. The dev LocalStack run destroys itself at the end of the CI job.

## Problems I hit

- The workstation disk is only 8 GB and each environment folder downloaded its own 675 MB AWS provider, so a Docker pull failed. I switched to one shared plugin cache.
- Terraform could not init the S3 backend for dev on LocalStack, so dev uses a local state override in CI.
- Deleting the repo-level secrets means the older lab workflows can't get AWS credentials until I refresh them again, which is what the assignment says will happen.

## Evidence

`assignment1/evidence/`: `pipeline-run.txt`, `prod-approval.txt`, `environments.txt`, `staging-output.txt`, `prod-output.txt`, `staging-state.txt`, `prod-state.txt`, `cloudwatch-alarms.txt`, `ssm-parameters.txt`, `web-check.txt`, `teardown.txt`.

## Conclusion

I now have one module deployed three times, with dev tested locally, staging deploying by itself and prod gated by a reviewer and a branch rule. The credentials are scoped to the environments, the password comes from SSM and the alarm is in Terraform. The part I would change first in a real account is replacing the stored session credentials with the OIDC role above.
