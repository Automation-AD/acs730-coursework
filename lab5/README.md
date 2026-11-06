# Lab 5 - Terraform Introduction and Reliable CI

## What I built

One Terraform configuration in `lab5/` that targets **real AWS or LocalStack from a single input**,
`use_localstack` (set to `true` by the committed `localstack.tfvars`).

| File | Contents |
|---|---|
| `versions.tf` | `required_version >= 1.9.0`, AWS provider `~> 5.60` (lock file pins 5.100.0) |
| `providers.tf` | One provider block, two targets: fake `test` keys, `skip_*` flags and a `dynamic "endpoints"` block only when `use_localstack` is true |
| `variables.tf` | 11 typed, described variables; validation on `project`, `vpc_cidr`, `instance_type`; `owner` has no default so it is mandatory |
| `network.tf` | 2 data sources (`aws_region`, `aws_availability_zones`), locals, VPC, subnets via `for_each`, internet gateway, route table, one association per subnet, security group built by `dynamic "ingress"` |
| `compute.tf` | AMI looked up with `data "aws_ami"` (counted out on LocalStack), `aws_instance.web` with `user_data` installing nginx and `depends_on` the route table associations, optional bucket gated by `count` |
| `outputs.tf` | `vpc_id`, `subnet_ids`, `web_public_ip`, `web_url`, `artifact_bucket`, `provider_target` |
| `../.github/workflows/lab5-ci.yml` | `fmt and validate` gate, then `plan and apply against LocalStack` (`needs: gates`), no secrets |

Every id is wired by attribute reference (`aws_vpc.main.id`, `aws_subnet.public[...].id`,
`aws_security_group.web.id`); no AMI, VPC, subnet or security group id is typed in. The only
literal `ami-` string is `var.localstack_ami_id`, a placeholder used only inside LocalStack.

Local run against LocalStack 3.8: `Plan: 10 to add` → `Apply complete! Resources: 10 added`,
`provider_target = "localstack (http://localhost:4566)"`, then `Destroy complete! Resources: 10 destroyed`.
`evidence/describe-vpcs-after-destroy.json` shows only LocalStack's own default VPC (172.31.0.0/16).

Deviation from the handout: `providers.tf` uses `skip_requesting_account_id`; the handout's
`skip_requester_charged` is not an argument of the AWS provider, and `terraform validate` rejects it
(`An argument named "skip_requester_charged" is not expected here`) as soon as a resource uses the provider.

## Why for_each here and count there

- **Subnets use `for_each`** because they are distinct things with stable names. The map key is part of the
  address (`aws_subnet.public["a"]`), and addresses are what Terraform compares between runs. Adding key `c`
  plans `1 to add`; removing `b` (Experiment 1) planned **`0 to add, 0 to change, 2 to destroy`**: subnet `b`
  and its route table association, with `a` and `c` untouched.
- **The same subnets with `count` are a trap.** Addresses are `[0] [1] [2]`; delete the middle entry and every
  later one shifts down a slot. Experiment 1 measured it: **`1 to add, 0 to change, 2 to destroy`**, with
  `counted[1] must be replaced` (it now has the third subnet's CIDR) and `counted[2] will be destroyed`. On real
  AWS that destroys a subnet that was supposed to stay, and anything inside it.
- **The bucket uses `count`** because the input is a yes/no about one resource: there are exactly two plans,
  `0 to add` or `1 to add`, and no key to keep stable. Count when the question is *how many*,
  for_each when the question is *which ones*.

## Why not plan and apply against real AWS on every pull request

- **It costs money per run, not per month.** Every pull request would build and destroy real infrastructure;
  27 students pushing a few times a week is thousands of create/destroy cycles against one fixed $50 pot.
  LocalStack costs nothing and leaves nothing behind once the container is removed.
- **It needs a long-lived AWS credential in the repository.** Applying from Actions means an access key in GitHub
  secrets that can leak and must be rotated. In an Academy account it cannot be scoped down, because IAM writes are
  denied, so the only key that works is a broad one. This workflow has no secret at all; the `test`/`test` pair in
  `providers.tf` is a required-field filler LocalStack accepts.
- **Academy sessions expire.** Lab credentials last a few hours, so a pull request opened on Saturday night goes red on
  Sunday morning for a reason unrelated to the code, people learn to ignore red checks, and a check people ignore is
  worse than no check.
- **It is slow and flaky.** Minutes each way, API rate limits, eventual-consistency errors unrelated to the change, and
  concurrent pull requests colliding on resource names and state in one shared account.
- **The honest limit of LocalStack.** A green LocalStack run proves the configuration is coherent and the dependency
  graph builds. It does not prove IAM is right (LocalStack does not enforce it) or that `user_data` works (LocalStack
  never boots the instance, and its "public IP" does not route). The real-AWS check belongs once, on merge or on a
  schedule, not on every pull request.

## Experiments

All run against LocalStack in a throwaway copy of this folder; every change was undone and nothing here was edited.

### 1. for_each vs count on the subnets

- **Prediction:** count over three CIDRs, remove the middle one → `1 to add, 0 to change, 2 to destroy`
  (index 1 is replaced with the third CIDR, index 2 is destroyed). for_each with keys `a,b,c`, remove `b` →
  `0 to add, 0 to change, 2 to destroy` (subnet `b` plus its association).
- **Result:** exactly that. count: `aws_subnet.counted[1] must be replaced`, `aws_subnet.counted[2] will be destroyed`,
  `Plan: 1 to add, 0 to change, 2 to destroy.` for_each: `aws_subnet.public["b"]` and `aws_route_table_association.public["b"]`
  `will be destroyed`, `Plan: 0 to add, 0 to change, 2 to destroy.`
- **Explanation:** count identifies a subnet by its position, so removing one shifts the identity of every subnet after it
  and Terraform "fixes" them by replacing them. for_each identifies it by key, so only the removed key changes.

### 2. Delete the depends_on

- **Prediction:** the plan does not change at all.
- **Result:** `Plan: 10 to add, 0 to change, 0 to destroy.` both with and without `depends_on`.
- **Explanation:** depends_on changes the *order*, not the *set*, of resources. Without it, the instance only depends on
  the subnet and security group it references, so Terraform may launch it before the route table association exists;
  user_data then runs at first boot with no default route, `dnf install nginx` hangs, and the instance comes up with no
  web server and no error. LocalStack never boots the instance or runs user_data, so the bug is invisible there; on
  real AWS `web_url` simply never answers.

### 4. Turn the bucket off

- **Prediction:** with `one()`, `terraform output artifact_bucket` prints `null`; with `[0]` the plan fails with an index error.
- **Result:** the second half was right: `Error: Invalid index ... aws_s3_bucket.artifacts is empty tuple`. The first half
  was not: Terraform does not store a null output at all, so `terraform output artifact_bucket` said
  `Error: Output "artifact_bucket" not found` and `terraform output` simply did not list it.
- **Explanation:** `[*]` turns the zero-or-one resource into a list and `one()` turns that into the value or null, so the
  configuration is valid in both states. `[0]` assumes the bucket exists and fails the whole plan when it does not, which
  would block every run with `create_artifact_bucket = false`.
