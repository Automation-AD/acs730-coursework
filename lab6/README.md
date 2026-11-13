# Lab 6 - Ansible config management and a Packer golden AMI

## Three required sentences

- **Runner-to-instance mechanism:** I used SSM Session Manager, because the instances need no inbound port 22 and the runner only uses the temporary session creds it already has, so there is no SSH key stored in repo secrets.
- **What changed=0 on a second run proves:** every task checked the real state of the host and found it already matched what the role wants, so the same playbook is safe to run on a fresh box, a converged box, or from the pipeline on every merge.
- **Why deregistering an AMI is not enough:** the AMI is just a pointer, the EBS snapshot behind it is the actual data and the thing that bills, and once the AMI is gone describe-images can't tell you which snapshot was its, so I read the snapshot id first and deleted it after.

## Layout

- `terraform/main.tf` - 2 x t3.micro AL2023, tagged `Lab=lab6`, `Role=web`, SG with only port 80 in, `iam_instance_profile = "LabInstanceProfile"`. No key pair, no port 22.
- `ansible/` - `ansible.cfg`, dynamic inventory `inventory/lab6.aws_ec2.yml` (tags only, no ids/IPs), `group_vars/role_web.yml` (aws_ssm connection), `site.yml` calling role `roles/webserver`.
- `packer/web.pkr.hcl` - bakes the same role into an AMI, plus `files/index.html` copied to `/opt/acs730-web/baked.html`.
- `scripts/boot-to-ready.sh` - polls until HTTP 200 and prints seconds since start.
- `.github/workflows/lab6-configure.yml` - plan on push, apply + Ansible converge on manual dispatch.

SSM needs an S3 bucket for file transfer (`acs730-lab6-ssm-<account>`). The bucket region and `ansible_aws_ssm_region` both have to be us-east-1, otherwise the first task fails with PermanentRedirect.

## Boot-to-ready

Same script, clock starts when I ask AWS for the instance, stops at the first HTTP 200.

| Path | Seconds | What is included |
|---|---|---|
| Converge-on-boot (stock AL2023 + Ansible over SSM) | 116 | launch, boot, SSM agent registering (~50 s), dnf, templates, service start |
| Golden AMI (Packer) | 21 | launch and boot only, service is already enabled in the image |

The Packer build itself took about 5 min (`evidence/packer-build.txt`).

In the slow path the Ansible logic is not the slow part. Most of it is waiting for the SSM agent to register and then dnf pulling packages, and that happens again on every instance.

The golden AMI moves the cost, it doesn't remove it. The work happens once at bake time instead of N times at launch. So it wins as soon as you launch more than a couple of instances, and loses for a single one since you paid a full build to save about 95 s.

What breaks with golden AMIs: the image is frozen, so patches released after the bake aren't in it and you need a rebuild schedule. You also can't see what's inside without the build log, while a playbook documents itself.

What breaks with converge-on-boot: every launch depends on package mirrors being up right then. A mirror outage means instances that boot and never get ready, which is bad for autoscaling at 3 a.m.

**Recommendation:** golden AMI, because web servers get launched in groups and scale-out needs to be fast and not depend on mirrors. I would switch to converge-on-boot if we only ran one or two long-lived boxes that change config often.

## Changes from the handout

- `install-lab-tools.sh lab6` only installed `amazon.aws` 12.1.0, which is too new for the AL2023 ansible-core 2.15 / Python 3.9, and it skipped `community.aws` and boto3. On the workstation I installed `amazon.aws` 9.5.0, `community.aws` 9.3.0 and boto3/botocore 1.40.0 into Ansible's Python.
- `main.tf` uses the S3 backend (`acs730-tfstate-<account>`, key `lab6/terraform.tfstate`, same as lab3). Without it the CI apply starts from empty state, makes two more instances and then forgets them. With it the CI apply was a no-op and the converge hit the real instances.
- Workflow: `python3 -m pip install` fails on ubuntu-24.04 (externally-managed-environment), so I added `actions/setup-python` with 3.12. I also pinned `ansible-core==2.16.14`, the collections, boto3 and the session-manager-plugin version (handout had `>=` and `latest`), and `runs-on: ubuntu-24.04`.
- Packer: `check-lab.sh` runs `packer validate` from the repo root, so the handout's relative paths failed. I prefixed `playbook_file` and the file source with `${path.root}/` so it validates from either folder. The AMI was built before this change, and the paths resolve to the same files.
- Packer: added `temporary_security_group_source_public_ip = true` so the throwaway build SG only opens 22 to the workstation IP instead of 0.0.0.0/0.

## Experiments

### 1. Break idempotency with a shell task

Added `ansible.builtin.shell: mkdir -p /opt/acs730-web/logs`.

- Prediction: changed=1 on every run, even though the dir exists after the first one.
- Result: changed=1 on both runs for both hosts.
- With `creates: /opt/acs730-web/logs` I predicted changed=0, and got changed=0 on both runs.

Ansible can't work this out itself because a shell command is just a string to it, so it has no idea what state the command is meant to produce. `creates:` tells it what to check. Reverted, removed the dir, re-ran: changed=0.

### 2. state: latest vs state: present

Changed the dnf task to `state: latest` and ran twice.

- Prediction: probably changed=0 today, but it depends on the day, since it reports changed whenever a newer python3 or rsync shows up in the repo.
- Result: changed=0 on both runs, because nothing new was published between the runs.

For a pipeline that runs on every merge I want `present`. `latest` makes the result depend on the date, can upgrade packages during an unrelated merge, and a "changed" stops meaning "someone changed the code". Updates should come from a deliberate AMI rebuild or a patch run. Reverted to `present`, changed=0.
